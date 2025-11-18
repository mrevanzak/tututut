import Combine
import ConvexMobile
import Foundation
import OSLog
import Observation
import UserNotifications

@MainActor
@Observable
final class TrainMapStore {
  private nonisolated(unsafe) let convexClient = Dependencies.shared.convexClient
  private let cacheService = TrainMapCacheService()
  private let liveActivityService = TrainLiveActivityService.shared
  private let proximityService = StationProximityService.shared
  private let configStore = ConfigStore.shared
  @ObservationIgnored private let notificationCenter = UNUserNotificationCenter.current()

  var isLoading: Bool = false
  var selectedMapStyle: MapStyleOption = .hybrid
  var selectedTrain: ProjectedTrain? {
    didSet {
      Task { await persistSelectedTrain() }
    }
  }

  var stations: [Station] = []
  var routes: [Route] = []
  var lastUpdatedAt: String?

  var selectedJourneyData: TrainJourneyData? {
    didSet {
      Task { await persistJourneyData() }
    }
  }

  // Pending train/journey data for alarm configuration
  var pendingTrainForAlarmConfiguration: ProjectedTrain?
  var pendingJourneyDataForAlarmConfiguration: TrainJourneyData?

  // Timestamp for triggering live position updates (must be observable)
  private var projectionTimestamp: Date = Date()

  @ObservationIgnored private var scheduledTripReminderRequestId: String?

  var liveTrainPosition: ProjectedTrain? {
    guard selectedTrain != nil, selectedJourneyData != nil else { return nil }
    // Access projectionTimestamp to establish dependency for observation
    _ = projectionTimestamp
    return projectSelectedTrain(now: Date())
  }

  @ObservationIgnored private var projectionTimer: Timer?
  @ObservationIgnored private var lastUpdatedAtCancellable: AnyCancellable?

  let logger = Logger(subsystem: "kreta", category: String(describing: TrainMapStore.self))

  init() {

    // Load cached data immediately on init for instant display
    _ = try? loadCachedDataIfAvailable()

    lastUpdatedAtCancellable = convexClient.subscribe(
      to: "gapeka:getLastUpdatedAt", yielding: String.self, captureTelemetry: true
    )
    .receive(on: DispatchQueue.main)
    .sink(
      receiveCompletion: { completion in
        switch completion {
        case .finished:
          break
        case .failure(let error):
          self.logger.error("LastUpdatedAt subscription error: \(error)")
        }
      },
      receiveValue: { lastUpdatedAt in
        self.lastUpdatedAt = lastUpdatedAt
      })
  }

  func loadData(at timestamp: String) async throws {
    isLoading = true
    defer { isLoading = false }

    stopProjectionUpdates()

    do {
      let cachedTimestamp = cacheService.getCachedTimestamp()

      let hasCompleteCache =
        cacheService.hasCachedStations()
        && cacheService.hasCachedRoutes()

      let needsUpdate = cachedTimestamp != timestamp || !hasCompleteCache

      if needsUpdate {

        async let routesResult: [RoutePolyline] = Task { @MainActor in
          try await convexClient.query(to: "routes:list", yielding: [RoutePolyline].self)
        }.value
        async let stationsResult: [Station] = Task { @MainActor in
          try await convexClient.query(to: "station:list", yielding: [Station].self)
        }.value

        do {
          let routePolylines = try await routesResult
          self.routes = routePolylines.map { Route(id: $0.id, name: $0.name, path: $0.path) }
          try cacheService.saveRoutes(routePolylines)
        } catch {
          logger.error("Routes fetch error: \(error)")
          throw TrainMapError.routesFetchFailed(error.localizedDescription)
        }

        do {
          let stations = try await stationsResult
          self.stations = stations
          try cacheService.saveStations(stations)

          // Update proximity triggers with new station data
          await proximityService.updateProximityTriggers(for: stations)
        } catch {
          logger.error("Stations fetch error: \(error)")
          throw TrainMapError.stationsFetchFailed(error.localizedDescription)
        }

      } else {
        try loadCachedData()

        // Update proximity triggers with cached station data
        await proximityService.updateProximityTriggers(for: stations)
      }

      startProjectionUpdates()
      try cacheService.saveTimestamp(timestamp)

    } catch let error as TrainMapError {
      logger.error("TrainMapError encountered: \(error)")
      throw error
    } catch {
      logger.error("Unexpected error: \(error)")
      throw TrainMapError.dataMappingFailed(error.localizedDescription)
    }
  }
}

// MARK: - Data loading helpers
extension TrainMapStore {
  fileprivate func loadCachedData() throws {
    stations = try cacheService.loadCachedStations()
    let routePolylines = try cacheService.loadCachedRoutes()
    routes = routePolylines.map { Route(id: $0.id, name: $0.name, path: $0.path) }
  }

  fileprivate func loadCachedDataIfAvailable() throws -> Bool {
    guard cacheService.hasCachedStations(), cacheService.hasCachedRoutes()
    else { return false }

    try loadCachedData()
    return true
  }
}

// MARK: - Projection management
extension TrainMapStore {
  func startProjectionUpdates(interval: TimeInterval = 1.0) {
    stopProjectionUpdates()
    logger.debug("Starting projection updates with interval: \(interval)s")
    let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        // Update timestamp to trigger liveTrainPosition recalculation
        self.projectionTimestamp = Date()
      }
    }
    projectionTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func stopProjectionUpdates() {
    if projectionTimer != nil {
      logger.debug("Stopping projection updates")
    }
    projectionTimer?.invalidate()
    projectionTimer = nil
  }
}

// MARK: - Selected train management
extension TrainMapStore {
  func selectTrain(
    _ train: ProjectedTrain,
    journeyData: TrainJourneyData,
    alarmOffsetMinutes: Int? = nil
  ) async throws {
    logger.info("=== selectTrain called ===")
    logger.info("Train: \(train.name, privacy: .public), ID: \(train.id, privacy: .public)")
    logger.info("From station: \(train.fromStation?.name ?? "nil", privacy: .public)")
    logger.info("To station: \(train.toStation?.name ?? "nil", privacy: .public)")
    logger.info("Departure: \(train.segmentDeparture?.description ?? "nil", privacy: .public)")
    logger.info("Journey data trainId: \(journeyData.trainId, privacy: .public)")

    selectedTrain = train
    selectedJourneyData = journeyData
    startProjectionUpdates()

    // Update proximity service that user now has active journey
    proximityService.updateJourneyStatus(hasActiveJourney: true)

    // Start Live Activity
    logger.info("Attempting to start Live Activity...")
    do {
      try await startLiveActivityForTrain(
        train: train,
        journeyData: journeyData,
        alarmOffsetMinutes: alarmOffsetMinutes
      )
      logger.info("Live Activity start completed successfully")
    } catch {
      logger.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
      logger.error("Error type: \(String(describing: type(of: error)), privacy: .public)")
      throw error
    }

    // Track journey start
    if let from = train.fromStation, let to = train.toStation {
      AnalyticsEventService.shared.trackJourneyStarted(
        trainId: journeyData.trainId,
        trainName: train.name,
        from: from,
        to: to,
        userSelectedDeparture: journeyData.userSelectedDepartureTime,
        userSelectedArrival: journeyData.userSelectedArrivalTime,
        hasAlarmEnabled: AlarmPreferences.shared.defaultAlarmEnabled
      )
    }
  }

  /// Validate if the alarm offset is appropriate for the journey timing
  func validateAlarmTiming(
    offsetMinutes: Int,
    departureTime: Date,
    arrivalTime: Date
  ) -> AlarmValidationResult {
    // Server already normalized times, use directly
    let now = Date()

    // Use rounded values to avoid truncation errors near boundaries
    let minutesUntilArrival = Int((arrivalTime.timeIntervalSince(now) / 60).rounded())
    let journeyDurationMinutes = Int((arrivalTime.timeIntervalSince(departureTime) / 60).rounded())

    // Guard: Validate input parameters
    guard offsetMinutes > 0 else {
      // This shouldn't happen (picker limits 1-60), but defensive programming
      // Treat as insufficient time (fallback case)
      return .invalid(
        .insufficientTimeForAlarm(
          minutesUntilArrival: minutesUntilArrival,
          requestedOffset: offsetMinutes
        ))
    }

    // Check 1: Validate journey data integrity
    // Departure must be before arrival
    if departureTime >= arrivalTime {
      // Invalid journey data - arrival before or equal to departure
      // Treat as journey too short (data integrity issue)
      return .invalid(
        .journeyTooShort(
          journeyDuration: journeyDurationMinutes,
          requestedOffset: offsetMinutes,
          minimumRequired: offsetMinutes + 10
        ))
    }

    // Check 2: Arrival time must be in the future
    // If arrival is in the past, alarm cannot be set
    if minutesUntilArrival <= 0 {
      return .invalid(
        .arrivalInPast(minutesUntilArrival: minutesUntilArrival)
      )
    }

    // Check 3: Arrival time must be greater than offset
    // If arrival time > offset time, the alarm can be set
    if minutesUntilArrival <= offsetMinutes {
      return .invalid(
        .insufficientTimeForAlarm(
          minutesUntilArrival: minutesUntilArrival,
          requestedOffset: offsetMinutes
        ))
    }

    // Check 4: Alarm time must be after departure
    // If offset >= journey duration, alarm would fire before train departs
    if offsetMinutes >= journeyDurationMinutes {
      return .invalid(
        .alarmBeforeDeparture(
          journeyDuration: journeyDurationMinutes,
          requestedOffset: offsetMinutes
        ))
    }

    // Check 5: Journey duration must be sufficient (offset + 10 minute buffer)
    // This ensures there's enough time for the alarm and some buffer
    let minimumRequiredDuration = offsetMinutes + 10
    if journeyDurationMinutes < minimumRequiredDuration {
      return .invalid(
        .journeyTooShort(
          journeyDuration: journeyDurationMinutes,
          requestedOffset: offsetMinutes,
          minimumRequired: minimumRequiredDuration
        ))
    }

    return .valid()
  }

  func applyAlarmConfiguration(
    offsetMinutes: Int,
    validationResult: AlarmValidationResult?,
    journeyDurationMinutes: Int? = nil
  ) async {
    let previousOffset = AlarmPreferences.shared.defaultAlarmOffsetMinutes
    let isInitialSetup = !AlarmPreferences.shared.hasCompletedInitialSetup

    AlarmPreferences.shared.defaultAlarmOffsetMinutes = offsetMinutes
    AlarmPreferences.shared.markInitialSetupComplete()

    let failureReasonDescription = validationResult?.reason
      .map(analyticsReasonDescription(for:))

    AnalyticsEventService.shared.trackAlarmConfigured(
      offsetMinutes: offsetMinutes,
      isValid: validationResult?.isValid ?? true,
      validationFailureReason: failureReasonDescription,
      isInitialSetup: isInitialSetup,
      previousOffsetMinutes: previousOffset != offsetMinutes ? previousOffset : nil,
      journeyDurationMinutes: journeyDurationMinutes
    )

    await liveActivityService.refreshAlarmConfiguration(
      alarmOffsetMinutes: offsetMinutes
    )
  }

  private func analyticsReasonDescription(
    for reason: AlarmValidationResult.AlarmValidationFailureReason
  ) -> String {
    switch reason {
    case let .arrivalInPast(minutesUntilArrival):
      return
        "arrival_in_past(minutes_until_arrival:\(minutesUntilArrival))"
    case let .insufficientTimeForAlarm(minutesUntilArrival, requestedOffset):
      return
        "insufficient_time_for_alarm(minutes_until_arrival:\(minutesUntilArrival), requested_offset:\(requestedOffset))"
    case let .alarmBeforeDeparture(journeyDuration, requestedOffset):
      return
        "alarm_before_departure(journey_duration:\(journeyDuration), requested_offset:\(requestedOffset))"
    case let .journeyTooShort(journeyDuration, requestedOffset, minimumRequired):
      return
        "journey_too_short(journey_duration:\(journeyDuration), requested_offset:\(requestedOffset), minimum_required:\(minimumRequired))"
    }
  }

  private func startLiveActivityForTrain(
    train: ProjectedTrain,
    journeyData: TrainJourneyData,
    alarmOffsetMinutes: Int? = nil
  ) async throws {
    logger.info("=== startLiveActivityForTrain called ===")
    logger.info("Train: \(train.name, privacy: .public)")

    // Validate required data
    guard let fromStation = train.fromStation,
      let toStation = train.toStation,
      let departureTime = train.segmentDeparture
    else {
      logger.error("❌ Missing required data for Live Activity")
      logger.error("  fromStation: \(train.fromStation?.name ?? "nil", privacy: .public)")
      logger.error("  toStation: \(train.toStation?.name ?? "nil", privacy: .public)")
      logger.error(
        "  departureTime: \(train.segmentDeparture?.description ?? "nil", privacy: .public)")
      throw TrainMapError.dataMappingFailed(
        "Missing required data for Live Activity: fromStation=\(train.fromStation != nil), toStation=\(train.toStation != nil), departureTime=\(train.segmentDeparture != nil)"
      )
    }

    logger.info("✅ Required data validated")
    logger.info(
      "  From: \(fromStation.name, privacy: .public) (\(fromStation.code, privacy: .public))")
    logger.info("  To: \(toStation.name, privacy: .public) (\(toStation.code, privacy: .public))")
    logger.info("  Departure: \(departureTime, privacy: .public)")

    let timeUntilDeparture = departureTime.timeIntervalSinceNow
    logger.info("Time until departure: \(timeUntilDeparture / 60) minutes")

    guard let scheduleOffset = configStore.appConfig?.tripReminder else {
      logger.error("❌ No trip reminder config found")
      logger.error("  appConfig exists: \(self.configStore.appConfig != nil)")
      throw TrainMapError.dataMappingFailed("No trip reminder configuration found")
    }

    logger.info("Schedule offset: \(scheduleOffset / 60) minutes")

    if timeUntilDeparture <= scheduleOffset {
      cancelPendingTripReminder()
      // Start immediately on device
      logger.info(
        "✅ Starting Live Activity immediately (departure in \(timeUntilDeparture / 60) minutes)")
      try await executeLiveActivityStart(
        train: train,
        journeyData: journeyData,
        alarmOffsetMinutes: alarmOffsetMinutes
      )
    } else {
      logger.info(
        "⏰ Queuing trip reminder notification (departure in \(timeUntilDeparture / 60) minutes)")

      try await scheduleTripReminderNotification(
        train: train,
        fromStation: fromStation,
        toStation: toStation,
        departureTime: departureTime,
        scheduleOffset: scheduleOffset
      )
    }
  }

  /// Execute Live Activity start and alarm scheduling logic
  /// This is the core logic that should be executed regardless of timing
  private func executeLiveActivityStart(
    train: ProjectedTrain,
    journeyData: TrainJourneyData,
    alarmOffsetMinutes: Int? = nil
  ) async throws {
    logger.info("=== executeLiveActivityStart called ===")

    guard let fromStation = train.fromStation,
      let toStation = train.toStation,
      let departureTime = train.segmentDeparture
    else {
      logger.error("❌ Missing required data in executeLiveActivityStart")
      logger.error("  fromStation: \(train.fromStation?.name ?? "nil", privacy: .public)")
      logger.error("  toStation: \(train.toStation?.name ?? "nil", privacy: .public)")
      logger.error(
        "  departureTime: \(train.segmentDeparture?.description ?? "nil", privacy: .public)")
      throw TrainMapError.dataMappingFailed("Missing required data in executeLiveActivityStart")
    }

    // Server already normalized times, use directly
    let now = Date()
    let isInProgress =
      (journeyData.userSelectedDepartureTime...journeyData.userSelectedArrivalTime).contains(now)

    logger.info("Journey state check:")
    logger.info("  Now: \(now, privacy: .public)")
    logger.info("  Departure: \(journeyData.userSelectedDepartureTime, privacy: .public)")
    logger.info("  Arrival: \(journeyData.userSelectedArrivalTime, privacy: .public)")
    logger.info("  Is in progress: \(isInProgress)")

    let finalAlarmOffset = alarmOffsetMinutes ?? AlarmPreferences.shared.defaultAlarmOffsetMinutes
    logger.info("Alarm offset: \(finalAlarmOffset) minutes")

    let fromTrainStation = TrainStation(
      name: fromStation.name,
      code: fromStation.code,
      estimatedTime: departureTime
    )
    let destinationTrainStation = TrainStation(
      name: toStation.name,
      code: toStation.code,
      estimatedTime: journeyData.userSelectedArrivalTime
    )

    logger.info("Created TrainStation for destination:")
    logger.info("  Name: \(destinationTrainStation.name, privacy: .public)")
    logger.info("  Code: \(destinationTrainStation.code, privacy: .public)")
    logger.info(
      "  Estimated Time: \(destinationTrainStation.estimatedTime?.description ?? "nil", privacy: .public)"
    )

    logger.info("Calling liveActivityService.start()...")
    logger.info("  Train name: \(train.name, privacy: .public)")
    logger.info(
      "  From: \(fromTrainStation.name, privacy: .public) (\(fromTrainStation.code, privacy: .public))"
    )
    logger.info(
      "  Destination: \(destinationTrainStation.name, privacy: .public) (\(destinationTrainStation.code, privacy: .public))"
    )
    logger.info("  Initial state: \(isInProgress ? "onBoard" : "beforeBoarding", privacy: .public)")

    do {
      let activity = try await liveActivityService.start(
        trainName: train.name,
        from: fromTrainStation,
        destination: destinationTrainStation,
        // seatClass: .economy(number: 1),  // TODO: Replace with actual seat class
        // seatNumber: "1A",  // TODO: Replace with actual seat number
        initialJourneyState: isInProgress ? .onBoard : nil,
        alarmOffsetMinutes: finalAlarmOffset
      )
      logger.info("✅ Live Activity created successfully")
      logger.info("  Activity ID: \(activity.id, privacy: .public)")
      logger.info(
        "  Activity state: \(activity.content.state.journeyState.rawValue, privacy: .public)")

      // Verify the activity is actually in the system
      let allActivities = liveActivityService.getActiveLiveActivities()
      logger.info("📊 Total active Live Activities after creation: \(allActivities.count)")
      if let foundActivity = allActivities.first(where: { $0.id == activity.id }) {
        logger.info("✅ Created activity found in active activities list")
        logger.info(
          "  Activity attributes - From: \(foundActivity.attributes.from.name, privacy: .public) (\(foundActivity.attributes.from.code, privacy: .public))"
        )
        logger.info(
          "  Activity attributes - Destination: \(foundActivity.attributes.destination.name, privacy: .public) (\(foundActivity.attributes.destination.code, privacy: .public))"
        )
        logger.info(
          "  Activity attributes - Destination time: \(foundActivity.attributes.destination.estimatedTime?.description ?? "nil", privacy: .public)"
        )
      } else {
        logger.error("❌ Created activity NOT found in active activities list!")
      }
    } catch {
      logger.error(
        "❌ Failed to create Live Activity: \(error.localizedDescription, privacy: .public)")
      logger.error("  Error type: \(String(describing: type(of: error)), privacy: .public)")
      if let nsError = error as NSError? {
        logger.error("  Domain: \(nsError.domain, privacy: .public)")
        logger.error("  Code: \(nsError.code)")
        logger.error("  UserInfo: \(nsError.userInfo, privacy: .public)")
      }
      throw error
    }
  }

  private func scheduleTripReminderNotification(
    train: ProjectedTrain,
    fromStation: Station,
    toStation: Station,
    departureTime: Date,
    scheduleOffset: TimeInterval
  ) async throws {
    let reminderDate = departureTime.addingTimeInterval(-scheduleOffset)

    guard reminderDate > Date() else {
      logger.info("Trip reminder would fire in the past; skipping local scheduling")
      return
    }

    cancelPendingTripReminder()

    let content = UNMutableNotificationContent()
    content.title = "Perjalanan akan dimulai"
    let minutes = scheduleOffset / 60
    let minutesText =
      minutes.truncatingRemainder(dividingBy: 1) == 0
      ? String(format: "%.0f", minutes)
      : String(format: "%.1f", minutes)
    content.body =
      "Kereta \(train.name) akan berangkat dalam \(minutesText) menit dari \(fromStation.name). Buka aplikasi untuk mulai melacak perjalanan."
    if let soundURL = Bundle.main.url(forResource: "alert", withExtension: "wav") {
      let sound = UNNotificationSound(named: UNNotificationSoundName(soundURL.absoluteString))
      content.sound = sound
    } else {
      content.sound = UNNotificationSound.default
    }
    content.categoryIdentifier = "TRIP_START_FALLBACK"
    content.interruptionLevel = .timeSensitive

    if let deepLink = makeTripReminderDeepLink(
      trainId: train.id,
      fromCode: fromStation.code,
      toCode: toStation.code
    ) {
      content.userInfo = ["deeplink": deepLink]
    }

    let components = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: reminderDate
    )

    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    let requestId = makeTripReminderIdentifier(for: train.id, departureTime: departureTime)
    let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)

    try await addNotificationRequest(request)
    scheduledTripReminderRequestId = requestId
  }

  private func addNotificationRequest(_ request: UNNotificationRequest) async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      notificationCenter.add(request) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }

  private func cancelPendingTripReminder() {
    guard let requestId = scheduledTripReminderRequestId else { return }
    notificationCenter.removePendingNotificationRequests(withIdentifiers: [requestId])
    notificationCenter.removeDeliveredNotifications(withIdentifiers: [requestId])
    scheduledTripReminderRequestId = nil
  }

  private func makeTripReminderIdentifier(for trainId: String, departureTime: Date) -> String {
    "trip_reminder_\(trainId)_\(Int(departureTime.timeIntervalSince1970))"
  }

  private func makeTripReminderDeepLink(trainId: String, fromCode: String, toCode: String)
    -> String?
  {
    var components = URLComponents()
    components.scheme = "kreta"
    components.host = "trip"
    components.path = "/start"
    components.queryItems = [
      URLQueryItem(name: "trainId", value: trainId),
      URLQueryItem(name: "fromCode", value: fromCode),
      URLQueryItem(name: "toCode", value: toCode),
    ]
    return components.url?.absoluteString
  }

  func clearSelectedTrain() async {
    // Evaluate completion vs cancellation before clearing
    if let train = selectedTrain, let data = selectedJourneyData {
      let now = Date()
      if now < data.userSelectedArrivalTime {
        AnalyticsEventService.shared.trackJourneyCancelled(
          trainId: data.trainId,
          reason: "ended_before_arrival",
          context: [
            "expected_arrival_time": ISO8601DateFormatter().string(
              from: data.userSelectedArrivalTime),
            "train_name": train.name,
          ]
        )
      } else {
        AnalyticsEventService.shared.trackJourneyCompleted(
          trainId: data.trainId,
          from: data.userSelectedFromStation,
          to: data.userSelectedToStation,
          userSelectedDeparture: data.userSelectedDepartureTime,
          completionType: "scheduled_arrival",
          actualArrival: now,
          wasTrackedUntilArrival: true
        )
      }
    }

    // End live activities and cancel alarms for the selected train
    if let selectedTrain = selectedTrain {
      let activeActivities = liveActivityService.getActiveLiveActivities()

      // Find matching activity by train name and stations
      for activity in activeActivities {
        let matchesTrainName = activity.attributes.trainName == selectedTrain.name
        let matchesFromStation =
          activity.attributes.from.code == selectedTrain.fromStation?.code
          || activity.attributes.from.name == selectedTrain.fromStation?.name
        let matchesDestination =
          activity.attributes.destination.code == selectedTrain.toStation?.code
          || activity.attributes.destination.name == selectedTrain.toStation?.name

        if matchesTrainName && matchesFromStation && matchesDestination {
          logger.info("Ending live activity \(activity.id) for train \(selectedTrain.name)")
          await liveActivityService.end(activityId: activity.id)
          break  // Only end one matching activity
        }
      }
    }

    cancelPendingTripReminder()

    // Update proximity service that user no longer has active journey
    proximityService.updateJourneyStatus(hasActiveJourney: false)

    selectedTrain = nil
    selectedJourneyData = nil
  }

  func loadSelectedTrainFromCache() async throws {
    selectedTrain = try cacheService.loadSelectedTrain()
    selectedJourneyData = try cacheService.loadJourneyData()

    // Update proximity service based on whether we have an active journey
    let hasJourney = selectedTrain != nil && selectedJourneyData != nil
    proximityService.updateJourneyStatus(hasActiveJourney: hasJourney)

    if selectedTrain != nil {
      startProjectionUpdates()
    }
  }

  /// Restart failed live activities for the current selected journey
  func restartFailedLiveActivityIfNeeded() async {
    guard let train = selectedTrain,
      let journeyData = selectedJourneyData,
      let fromStation = train.fromStation,
      let toStation = train.toStation
    else {
      logger.debug("No selected journey data available for restarting live activity")
      return
    }

    logger.info(
      "Checking if live activity needs to be restarted for train \(train.name, privacy: .public)")

    // Check if an activity already exists
    let existingActivities = liveActivityService.getActiveLiveActivities()
    let hasActivity = existingActivities.contains { activity in
      activity.attributes.trainName == train.name
        && activity.attributes.from.code == fromStation.code
        && activity.attributes.destination.code == toStation.code
    }

    guard !hasActivity else {
      return
    }

    do {
      // Server already normalized arrival time, use directly

      let fromTrainStation = TrainStation(
        name: fromStation.name,
        code: fromStation.code,
        estimatedTime: train.segmentDeparture
      )
      let destinationTrainStation = TrainStation(
        name: toStation.name,
        code: toStation.code,
        estimatedTime: journeyData.userSelectedArrivalTime
      )

      let now = Date()
      let isInProgress =
        (journeyData.userSelectedDepartureTime...journeyData.userSelectedArrivalTime).contains(now)

      let alarmOffset = AlarmPreferences.shared.defaultAlarmOffsetMinutes

      try await liveActivityService.restartFailedActivity(
        trainName: train.name,
        from: fromTrainStation,
        destination: destinationTrainStation,
        initialJourneyState: isInProgress ? .onBoard : nil,
        alarmOffsetMinutes: alarmOffset
      )
    } catch {
      logger.error(
        "Failed to restart live activity: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Start trip from deep link (notification handler)
  /// Tries cache first, then falls back to server fetch if needed
  func startFromDeepLink(trainId: String, fromCode: String, toCode: String) async throws {

    // Try cache first (most common case - user just created the journey)
    do {
      try await loadSelectedTrainFromCache()

      // Verify cached train matches the trainId from notification
      if let cachedJourneyData = selectedJourneyData,
        cachedJourneyData.trainId == trainId,
        selectedTrain != nil
      {
        logger.info("Using cached train data for trainId: \(trainId)")

        // Ensure stations and routes are loaded
        if stations.isEmpty || routes.isEmpty {
          if (try? loadCachedDataIfAvailable()) == true {
            // Cache loaded successfully, check if we still need data
          }
          // If still empty, we need to load from server
          if stations.isEmpty || routes.isEmpty {
            if let lastUpdatedAt = lastUpdatedAt {
              try await loadData(at: lastUpdatedAt)
            } else {
              // Fallback: try to get lastUpdatedAt from server
              let timestamp: String = try await convexClient.query(
                to: "gapeka:getLastUpdatedAt", yielding: String.self
              )
              try await loadData(at: timestamp)
            }
          }
        }

        // Use cached train directly - it was already projected when the journey was created
        // and remains valid. Re-projecting risks station ID lookup failures.
        guard let cachedTrain = selectedTrain else {
          throw TrainMapError.dataMappingFailed("Cached train data is missing")
        }

        // Live updates will work via liveTrainPosition computed property
        startProjectionUpdates()

        // Execute Live Activity start (by now it should be <= 10 minutes until departure)
        try await executeLiveActivityStart(train: cachedTrain, journeyData: cachedJourneyData)

        // Track journey start using cached train data
        if let from = cachedTrain.fromStation, let to = cachedTrain.toStation {
          AnalyticsEventService.shared.trackJourneyStarted(
            trainId: cachedJourneyData.trainId,
            trainName: cachedTrain.name,
            from: from,
            to: to,
            userSelectedDeparture: cachedJourneyData.userSelectedDepartureTime,
            userSelectedArrival: cachedJourneyData.userSelectedArrivalTime,
            hasAlarmEnabled: AlarmPreferences.shared.defaultAlarmEnabled
          )
        }

        return
      }
    } catch {
      // Cache miss or error - will fetch from server below
    }

    // Cache miss or doesn't match - fetch from server

    // Ensure stations and routes are loaded
    if stations.isEmpty || routes.isEmpty {
      if let lastUpdatedAt = lastUpdatedAt {
        try await loadData(at: lastUpdatedAt)
      } else {
        let timestamp: String = try await convexClient.query(
          to: "gapeka:getLastUpdatedAt", yielding: String.self
        )
        try await loadData(at: timestamp)
      }
    }

    // Fetch journey segments
    let journeyService = JourneyService()
    let selectedDate = Date()  // Deep link trips use today's date
    let segments = try await journeyService.fetchSegmentsForTrain(
      trainId: trainId,
      selectedDate: selectedDate
    )

    guard !segments.isEmpty else {
      throw TrainMapError.dataMappingFailed("No journey segments found for trainId: \(trainId)")
    }

    logger.info(
      "Building journey from server data: trainId=\(trainId, privacy: .public), fromCode=\(fromCode, privacy: .public), toCode=\(toCode, privacy: .public)"
    )

    // Find stations using code-based lookup (from deep link parameters)
    guard
      let stationPair = StationLookupHelper.findStationsByCodes(
        fromCode: fromCode,
        toCode: toCode,
        in: self.stations
      )
    else {
      logger.error(
        "Could not find stations for codes: fromCode=\(fromCode, privacy: .public), toCode=\(toCode, privacy: .public)"
      )
      throw TrainMapError.dataMappingFailed(
        "Could not find stations for journey using codes: fromCode=\(fromCode), toCode=\(toCode)")
    }

    let fromStation = stationPair.from
    let toStation = stationPair.to

    // Validate journey data
    if let validationError = JourneyDataBuilder.validateJourneyData(
      rows: segments,
      fromStation: fromStation,
      toStation: toStation
    ) {
      logger.warning("Journey validation warning: \(validationError, privacy: .public)")
    }

    guard let firstSegment = segments.first else {
      logger.error("No segments found for trainId: \(trainId, privacy: .public)")
      throw TrainMapError.dataMappingFailed("Invalid journey segments")
    }

    // Build journey segments and collect stations using JourneyDataBuilder
    // Server already normalized times to selectedDate
    let stationsById = StationLookupHelper.buildStationsById(self.stations)
    let (journeySegments, allStationsInJourney) = JourneyDataBuilder.buildSegmentsAndStations(
      from: segments,
      stationsById: stationsById
    )

    // Build TrainJourneyData
    // Server already normalized times, use directly
    guard let lastSegment = segments.last else {
      throw TrainMapError.dataMappingFailed("No segments found")
    }
    let journeyData = JourneyDataBuilder.buildTrainJourneyData(
      trainId: trainId,
      segments: journeySegments,
      allStations: allStationsInJourney,
      fromStation: fromStation,
      toStation: toStation,
      userSelectedDepartureTime: firstSegment.departure,
      userSelectedArrivalTime: lastSegment.arrival,
      selectedDate: selectedDate
    )

    // Build TrainJourney for projection
    let trainJourney = JourneyDataBuilder.buildTrainJourney(
      trainId: trainId,
      trainCode: firstSegment.trainCode,
      trainName: firstSegment.trainName,
      segments: journeySegments
    )

    // Build comprehensive station lookup for projection
    let projectionStationsById = StationLookupHelper.buildComprehensiveLookup(
      stations: self.stations,
      journeyStations: allStationsInJourney
    )

    let routesById = Dictionary(uniqueKeysWithValues: routes.map { ($0.id, $0) })

    // Station lookup diagnostics
    logger.debug(
      """
      Server fallback: Projecting train with \(projectionStationsById.count) stations mapped. \
      First segment: \(journeySegments.first?.fromStationId ?? "none") → \
      \(journeySegments.first?.toStationId ?? "none")
      """)

    guard
      let projectedTrain = TrainProjector.projectTrain(
        now: Date(),
        journey: trainJourney,
        stationsById: projectionStationsById,
        routesById: routesById,
        selectedDate: Date()  // Deep link trips use today's date
      )
    else {
      throw TrainMapError.dataMappingFailed("Failed to project train")
    }

    // Set selected train and journey data
    selectedTrain = projectedTrain
    selectedJourneyData = journeyData
    startProjectionUpdates()

    // Execute Live Activity start
    try await executeLiveActivityStart(train: projectedTrain, journeyData: journeyData)

    // Track journey start
    if let from = projectedTrain.fromStation, let to = projectedTrain.toStation {
      AnalyticsEventService.shared.trackJourneyStarted(
        trainId: journeyData.trainId,
        trainName: projectedTrain.name,
        from: from,
        to: to,
        userSelectedDeparture: journeyData.userSelectedDepartureTime,
        userSelectedArrival: journeyData.userSelectedArrivalTime,
        hasAlarmEnabled: AlarmPreferences.shared.defaultAlarmEnabled
      )
    }
  }

  private func persistSelectedTrain() async {
    do {
      try cacheService.saveSelectedTrain(selectedTrain)
    } catch {
      logger.error("Failed to save selected train: \(error)")
    }
  }

  private func persistJourneyData() async {
    do {
      try cacheService.saveJourneyData(selectedJourneyData)
    } catch {
      logger.error("Failed to save journey data: \(error)")
    }
  }

  private func projectSelectedTrain(now: Date = Date()) -> ProjectedTrain? {
    guard let selectedTrain, let selectedJourneyData else {
      logger.debug("Cannot project train: selectedTrain or selectedJourneyData is nil")
      return nil
    }

    logger.debug(
      "Projecting train '\(selectedTrain.name, privacy: .public)' at \(now, privacy: .public)")

    // Build comprehensive station lookup with multi-strategy approach
    let stationsById = StationLookupHelper.buildComprehensiveLookup(
      stations: stations,
      journeyStations: selectedJourneyData.allStations
    )

    let routesById = Dictionary(uniqueKeysWithValues: routes.map { ($0.id, $0) })

    // Use trainId from journeyData, not selectedTrain.id (which may be journey ID)
    let trainJourney = JourneyDataBuilder.buildTrainJourney(
      trainId: selectedJourneyData.trainId,
      trainCode: selectedTrain.code,
      trainName: selectedTrain.name,
      segments: selectedJourneyData.segments
    )

    guard
      let projected = TrainProjector.projectTrain(
        now: now,
        journey: trainJourney,
        stationsById: stationsById,
        routesById: routesById,
        selectedDate: selectedJourneyData.selectedDate
      )
    else {
      logger.error("Failed to project train '\(selectedTrain.name, privacy: .public)'")
      return nil
    }

    logger.debug("Successfully projected train '\(projected.name, privacy: .public)'")
    return projected
  }
}

// MARK: - Mapping helpers
extension TrainMapStore {
  static var preview: TrainMapStore {
    let store = TrainMapStore()
    store.stations = [
      Station(
        id: "GMR",
        code: "GMR",
        name: "Gambir",
        position: Position(latitude: -6.1774, longitude: 106.8306),
        city: nil
      ),
      Station(
        id: "JNG",
        code: "JNG",
        name: "Jatinegara",
        position: Position(latitude: -6.2149, longitude: 106.8707),
        city: nil
      ),
    ]
    store.routes = [
      Route(
        id: "L1",
        name: "Central Line",
        path: [
          Position(latitude: -6.1774, longitude: 106.8306),
          Position(latitude: -6.1900, longitude: 106.8450),
          Position(latitude: -6.2050, longitude: 106.8600),
          Position(latitude: -6.2149, longitude: 106.8707),
        ],
      )
    ]
    return store
  }
}
