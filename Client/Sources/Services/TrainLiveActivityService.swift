@preconcurrency import ActivityKit
import AlarmKit
import ConvexMobile
import Foundation
import OSLog

// MARK: - LiveActivityRegistry

actor LiveActivityRegistry {
  private struct AlarmSnapshot: Equatable {
    let arrivalTime: Date
    let offsetMinutes: Int
    let alarmEnabled: Bool
  }

  private var hasStartedMonitoring = false
  private var timers: [String: Task<Void, Never>] = [:]
  private var alarmSnapshots: [String: AlarmSnapshot] = [:]

  func startMonitoringIfNeeded() -> Bool {
    guard !hasStartedMonitoring else { return false }
    hasStartedMonitoring = true
    return true
  }

  func storeTimer(_ task: Task<Void, Never>, for activityId: String) -> Task<Void, Never>? {
    let existing = timers[activityId]
    timers[activityId] = task
    return existing
  }

  func removeTimer(for activityId: String) -> Task<Void, Never>? {
    timers.removeValue(forKey: activityId)
  }

  func drainTimers() -> [Task<Void, Never>] {
    let all = Array(timers.values)
    timers.removeAll()
    return all
  }

  func shouldScheduleAlarm(
    activityId: String,
    arrivalTime: Date,
    offsetMinutes: Int,
    alarmEnabled: Bool,
    force: Bool = false
  ) -> Bool {
    guard alarmEnabled else {
      alarmSnapshots.removeValue(forKey: activityId)
      return false
    }

    let snapshot = AlarmSnapshot(
      arrivalTime: arrivalTime,
      offsetMinutes: offsetMinutes,
      alarmEnabled: alarmEnabled
    )

    if force {
      alarmSnapshots[activityId] = snapshot
      return true
    }

    guard alarmSnapshots[activityId] != snapshot else { return false }
    alarmSnapshots[activityId] = snapshot
    return true
  }

  func clearAlarmSnapshot(for activityId: String) {
    alarmSnapshots.removeValue(forKey: activityId)
  }
}

// MARK: - TrainLiveActivityService

final class TrainLiveActivityService: @unchecked Sendable {
  static let shared = TrainLiveActivityService()

  // MARK: - Constants

  enum Constants {
    static let maxRetryAttempts = 3
    static let baseRetryDelay: Double = 0.5
    static let nanosecondsPerSecond: UInt64 = 1_000_000_000
    static let retryJitterNanoseconds: UInt64 = 50_000_000
  }

  // MARK: - Properties

  private let convexClient: ConvexClient
  private let logger = Logger(subsystem: "kreta", category: "TrainLiveActivityService")
  private let stateRegistry = LiveActivityRegistry()
  private let cacheService = TrainMapCacheService()

  private init(
    convexClient: ConvexClient = Dependencies.shared.convexClient
  ) {
    self.convexClient = convexClient
  }

  // MARK: - Activity Lifecycle

  @MainActor
  func start(
    trainName: String,
    from: TrainStation,
    destination: TrainStation,
    // seatClass: SeatClass,
    // seatNumber: String,
    initialJourneyState: JourneyState? = nil,
    alarmOffsetMinutes: Int = AlarmPreferences.shared.defaultAlarmOffsetMinutes
  ) async throws -> Activity<TrainActivityAttributes> {
    let activity: Activity<TrainActivityAttributes>
    do {
      activity = try await createActivity(
        trainName: trainName,
        from: from,
        destination: destination,
        // seatClass: seatClass,
        // seatNumber: seatNumber,
        initialJourneyState: initialJourneyState
      )
    } catch {
      logger.error("Failed to create Activity: \(error.localizedDescription, privacy: .public)")
      throw error
    }

    await setupActivityMonitoring(
      for: activity,
      destination: destination,
      trainName: trainName,
      alarmOffsetMinutes: alarmOffsetMinutes
    )

    return activity
  }

  @MainActor
  private func createActivity(
    trainName: String,
    from: TrainStation,
    destination: TrainStation,
    // seatClass: SeatClass,
    // seatNumber: String,
    initialJourneyState: JourneyState? = nil
  ) async throws -> Activity<TrainActivityAttributes> {
    let attributes = TrainActivityAttributes(
      trainName: trainName,
      from: from,
      destination: destination,
      // seatClass: seatClass,
      // seatNumber: seatNumber
    )

    let initialState = initialJourneyState ?? .beforeBoarding
    let contentState = TrainActivityAttributes.ContentState(journeyState: initialState)
    let content = ActivityContent(
      state: contentState, staleDate: destination.estimatedTime?.addingTimeInterval(10 * 60))

    do {
      return try Activity<TrainActivityAttributes>.request(
        attributes: attributes,
        content: content,
        pushType: .token
      )
    } catch {
      logger.error("Activity.request() failed: \(error.localizedDescription, privacy: .public)")
      throw error
    }
  }

  @MainActor
  private func setupActivityMonitoring(
    for activity: Activity<TrainActivityAttributes>,
    destination: TrainStation,
    trainName: String,
    alarmOffsetMinutes: Int = AlarmPreferences.shared.defaultAlarmOffsetMinutes
  ) async {
    let activityId = activity.id
    let alarmEnabled = AlarmPreferences.shared.defaultAlarmEnabled

    startMonitoringPushTokens(for: activity)

    // Safety: if departure is already in the past and state is still beforeBoarding,
    // immediately transition to onBoard to reflect in-progress journeys.
    if let departure = activity.attributes.from.estimatedTime,
      departure <= Date(),
      activity.content.state.journeyState == .beforeBoarding
    {
      await transitionToOnBoard(activityId: activityId)
    }

    await startAutomaticTransitions(for: activity)

    runBackgroundJob(label: "scheduleAlarm") { service in
      await service.scheduleAlarmIfEnabled(
        activityId: activityId,
        alarmEnabled: alarmEnabled,
        alarmOffsetMinutes: alarmOffsetMinutes,
        arrivalTime: destination.estimatedTime,
        trainName: trainName,
        destinationName: destination.name,
        destinationCode: destination.code
      )
    }

    runBackgroundJob(label: "scheduleServerArrival") { service in
      await service.scheduleServerArrivalAlert(trainName: trainName, destination: destination)
    }

    runBackgroundJob(label: "scheduleServerState") { service in
      await service.scheduleServerStateUpdates(
        activityId: activityId,
        trainName: trainName,
        origin: activity.attributes.from,
        destination: destination,
        arrivalLeadMinutes: Double(alarmOffsetMinutes)
      )
    }
  }

  @MainActor
  func update(
    activityId: String,
    journeyState: JourneyState? = nil
  ) async {
    guard let activity = findActivity(with: activityId) else { return }

    let contentState = activity.content.state
    let newContentState = TrainActivityAttributes.ContentState(
      journeyState: journeyState ?? contentState.journeyState,
    )
    await activity.update(
      ActivityContent(
        state: newContentState,
        staleDate: activity.attributes.destination.estimatedTime?.addingTimeInterval(10 * 60)))
  }

  func getActiveLiveActivities() -> [Activity<TrainActivityAttributes>] {
    Activity<TrainActivityAttributes>.activities
  }

  private func findActivity(with activityId: String) -> Activity<TrainActivityAttributes>? {
    Activity<TrainActivityAttributes>.activities.first { $0.id == activityId }
  }

  @MainActor
  func refreshInForeground(currentDate: Date = Date()) async {
    var foundActivity = false
    // Refresh existing activities
    for activity in Activity<TrainActivityAttributes>.activities {
      var currentState = activity.content.state.journeyState

      if currentState == .beforeBoarding,
        let departureTime = activity.attributes.from.estimatedTime,
        departureTime <= currentDate
      {
        await transitionToOnBoard(activityId: activity.id)
        currentState = .onBoard
      }

      if currentState != .prepareToDropOff,
        let arrivalTime = activity.attributes.destination.estimatedTime,
        arrivalTime <= currentDate
      {
        await transitionToPrepareToDropOff(activityId: activity.id)
        currentState = .prepareToDropOff
      }

      foundActivity = true
      await rescheduleAlarmIfNeeded(for: activity)
    }

    guard !foundActivity else {
      return
    }

    // Check for cached journey data and restart failed activities if needed
    await restartFailedActivityIfNeeded()
  }

  /// Restart failed live activity if cached journey data exists but no matching activity is found
  @MainActor
  private func restartFailedActivityIfNeeded() async {
    // Load cached journey data
    guard let train = try? cacheService.loadSelectedTrain(),
      let journeyData = try? cacheService.loadJourneyData(),
      let fromStation = train.fromStation,
      let toStation = train.toStation
    else {
      return
    }

    // Check if an activity already exists for this journey
    let existingActivities = getActiveLiveActivities()
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

      try await restartFailedActivity(
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

  /// Restart a live activity for a journey that should have one but doesn't
  @MainActor
  func restartFailedActivity(
    trainName: String,
    from: TrainStation,
    destination: TrainStation,
    initialJourneyState: JourneyState? = nil,
    alarmOffsetMinutes: Int = AlarmPreferences.shared.defaultAlarmOffsetMinutes
  ) async throws {
    // Check if an activity already exists for this journey
    let existingActivity = Activity<TrainActivityAttributes>.activities.first { activity in
      activity.attributes.trainName == trainName
        && activity.attributes.from.code == from.code
        && activity.attributes.destination.code == destination.code
    }

    guard existingActivity == nil else {
      return
    }

    // Start the activity
    _ = try await start(
      trainName: trainName,
      from: from,
      destination: destination,
      initialJourneyState: initialJourneyState,
      alarmOffsetMinutes: alarmOffsetMinutes
    )
  }

  @MainActor
  func transitionToOnBoard(activityId: String) async {
    await update(activityId: activityId, journeyState: .onBoard)
    if let activity = findActivity(with: activityId) {
      AnalyticsEventService.shared.trackLiveActivityStateChanged(
        activityId: activityId,
        state: "onBoard",
        trainName: activity.attributes.trainName
      )
    }
  }

  @MainActor
  func transitionToPrepareToDropOff(activityId: String) async {
    await update(activityId: activityId, journeyState: .prepareToDropOff)
    if let activity = findActivity(with: activityId) {
      AnalyticsEventService.shared.trackLiveActivityStateChanged(
        activityId: activityId,
        state: "prepareToDropOff",
        trainName: activity.attributes.trainName
      )
    }
  }

  // MARK: - State Transitions

  @MainActor
  func startAutomaticTransitions(for activity: Activity<TrainActivityAttributes>) async {
    let activityId = activity.id
    let timerTask = Task<Void, Never> { @MainActor [weak self] in
      guard let self else { return }
      await self.scheduleDepartureTransition(for: activityId)
      _ = await self.stateRegistry.removeTimer(for: activityId)
    }

    let previousTimer = await stateRegistry.storeTimer(timerTask, for: activityId)
    previousTimer?.cancel()
  }

  @MainActor
  private func scheduleDepartureTransition(
    for activityId: String
  ) async {
    guard let activity = findActivity(with: activityId) else { return }
    guard let departureTime = activity.attributes.from.estimatedTime else { return }

    let delay = max(0, departureTime.timeIntervalSinceNow)
    guard delay > 0 else {
      await transitionToOnBoard(activityId: activityId)
      return
    }

    let delayNanoseconds = UInt64(delay * Double(Constants.nanosecondsPerSecond))
    do {
      try await Task.sleep(nanoseconds: delayNanoseconds)
    } catch is CancellationError {
      return
    } catch {
      logger.error(
        "Departure transition timer failed: \(error.localizedDescription, privacy: .public)")
      return
    }

    guard !Task.isCancelled else { return }
    await transitionToOnBoard(activityId: activityId)
  }

  // MARK: - Alarm Management

  private func scheduleAlarmIfEnabled(
    activityId: String,
    alarmEnabled: Bool,
    alarmOffsetMinutes: Int,
    arrivalTime: Date?,
    trainName: String,
    destinationName: String,
    destinationCode: String,
    force: Bool = false
  ) async {
    guard !Task.isCancelled else {
      logger.debug(
        "Task cancelled, skipping alarm scheduling for activityId: \(activityId, privacy: .public)")
      return
    }

    guard alarmEnabled else {
      logger.debug(
        "Alarm disabled, clearing snapshot for activityId: \(activityId, privacy: .public)")
      await stateRegistry.clearAlarmSnapshot(for: activityId)
      return
    }

    guard let arrivalTime = arrivalTime else {
      logger.warning(
        "No arrival time provided, clearing alarm snapshot for activityId: \(activityId, privacy: .public)"
      )
      await stateRegistry.clearAlarmSnapshot(for: activityId)
      return
    }

    guard
      await stateRegistry.shouldScheduleAlarm(
        activityId: activityId,
        arrivalTime: arrivalTime,
        offsetMinutes: alarmOffsetMinutes,
        alarmEnabled: alarmEnabled,
        force: force
      )
    else {
      logger.debug(
        "Alarm already scheduled with same parameters for activityId: \(activityId, privacy: .public)"
      )
      return
    }

    logger.info(
      "Scheduling alarm for activityId: \(activityId, privacy: .public), arrivalTime: \(arrivalTime, privacy: .public), offsetMinutes: \(alarmOffsetMinutes)"
    )

    do {
      let alarmTime = arrivalTime.addingTimeInterval(-Double(alarmOffsetMinutes * 60))
      try await TrainAlarmService.shared.scheduleArrivalAlarm(
        activityId: activityId,
        arrivalTime: arrivalTime,
        offsetMinutes: alarmOffsetMinutes,
        trainName: trainName,
        destinationName: destinationName,
        destinationCode: destinationCode
      )
      logger.info("Successfully scheduled alarm for activityId: \(activityId, privacy: .public)")
      AnalyticsEventService.shared.trackAlarmScheduled(
        activityId: activityId,
        arrivalTime: arrivalTime,
        offsetMinutes: alarmOffsetMinutes,
        destinationCode: destinationCode,
        trainName: trainName,
        destinationName: destinationName,
        alarmTime: alarmTime
      )
    } catch {
      await stateRegistry.clearAlarmSnapshot(for: activityId)
      logger.error(
        "Failed to schedule alarm for activityId: \(activityId, privacy: .public), error: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func scheduleAlarmIfEnabled(for activity: Activity<TrainActivityAttributes>) async {
    let alarmEnabled = AlarmPreferences.shared.defaultAlarmEnabled
    let alarmOffsetMinutes = AlarmPreferences.shared.defaultAlarmOffsetMinutes

    await scheduleAlarmIfEnabled(
      activityId: activity.id,
      alarmEnabled: alarmEnabled,
      alarmOffsetMinutes: alarmOffsetMinutes,
      arrivalTime: activity.attributes.destination.estimatedTime,
      trainName: activity.attributes.trainName,
      destinationName: activity.attributes.destination.name,
      destinationCode: activity.attributes.destination.code
    )
  }

  // MARK: - Concurrency Helpers

  @discardableResult
  private func runBackgroundJob(
    label: StaticString,
    priority: TaskPriority = .background,
    operation: @escaping @Sendable (TrainLiveActivityService) async -> Void
  ) -> Task<Void, Never> {
    Task(priority: priority) { [weak self] in
      guard let self else { return }
      guard !Task.isCancelled else { return }
      await operation(self)
    }
  }

  @MainActor
  func end(
    activityId: String,
    dismissalPolicy: ActivityUIDismissalPolicy = .immediate
  ) async {
    await cancelTimer(for: activityId)
    await stateRegistry.clearAlarmSnapshot(for: activityId)
    await TrainAlarmService.shared.cancelArrivalAlarm(
      activityId: activityId, reason: "journey_ended", wasTriggered: false)

    guard let activity = findActivity(with: activityId) else { return }
    await activity.end(nil, dismissalPolicy: dismissalPolicy)
  }

  @MainActor
  func endAllImmediately() async {
    await cancelAllTimers()
    await TrainAlarmService.shared.cancelAllAlarms(reason: "manual_cancel")

    for activity in Activity<TrainActivityAttributes>.activities {
      await stateRegistry.clearAlarmSnapshot(for: activity.id)
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  private func cancelTimer(for activityId: String) async {
    let timer = await stateRegistry.removeTimer(for: activityId)
    timer?.cancel()
  }

  private func cancelAllTimers() async {
    let timers = await stateRegistry.drainTimers()
    timers.forEach { $0.cancel() }
  }

  // MARK: - Monitoring

  // MARK: - Server Arrival Alert Scheduling

  private func scheduleServerArrivalAlert(
    trainName: String,
    destination: TrainStation
  ) async {
    guard !Task.isCancelled else {
      logger.debug("Task cancelled, skipping server arrival alert scheduling")
      return
    }

    guard let deviceToken = PushRegistrationService.shared.currentToken() else {
      logger.warning("No device token available for server arrival alert scheduling")
      return
    }

    guard let arrivalTime = destination.estimatedTime else {
      logger.warning(
        "No arrival time available for server arrival alert scheduling, trainName: \(trainName, privacy: .public)"
      )
      return
    }

    logger.debug(
      "Scheduling server arrival alert for trainName: \(trainName, privacy: .public), destination: \(destination.code, privacy: .public)"
    )

    let arrivalMs = Double(arrivalTime.timeIntervalSince1970 * 1000)

    do {
      let _: String = try await convexClient.mutation(
        "notifications:scheduleArrivalAlert",
        with: [
          "deviceToken": deviceToken,
          "trainId": nil as String?,
          "trainName": trainName,
          "arrivalTime": arrivalMs,
          "destinationStation": [
            "name": destination.name,
            "code": destination.code,
            "estimatedTime": arrivalMs,
          ],
        ],
        captureTelemetry: true
      )
      logger.debug("Successfully scheduled server arrival alert")
    } catch {
      logger.error(
        "Failed to schedule server arrival alert: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func scheduleServerStateUpdates(
    activityId: String,
    trainName: String,
    origin: TrainStation,
    destination: TrainStation,
    arrivalLeadMinutes: Double
  ) async {
    guard !Task.isCancelled else {
      logger.debug("Task cancelled, skipping server state updates scheduling")
      return
    }

    let departureTimeMs = origin.estimatedTime.map { Double($0.timeIntervalSince1970 * 1000) }
    let arrivalTimeMs = destination.estimatedTime.map { Double($0.timeIntervalSince1970 * 1000) }

    guard departureTimeMs != nil || arrivalTimeMs != nil else {
      logger.warning(
        "No departure or arrival time available for server state updates, activityId: \(activityId, privacy: .public)"
      )
      return
    }

    logger.debug(
      "Scheduling server state updates for activityId: \(activityId, privacy: .public), trainName: \(trainName, privacy: .public)"
    )

    struct ScheduleResponse: Decodable {
      let departureScheduled: Bool
      let arrivalScheduled: Bool
    }

    let arrivalLeadMs = max(0, arrivalLeadMinutes) * 60 * 1000

    do {
      let _: ScheduleResponse = try await convexClient.mutation(
        "liveActivities:scheduleStateUpdates",
        with: [
          "activityId": activityId,
          "trainName": trainName,
          "departureTime": departureTimeMs,
          "arrivalTime": arrivalTimeMs,
          "arrivalLeadTimeMs": arrivalLeadMs,
        ],
        captureTelemetry: true
      )
      logger.debug("Successfully scheduled server state updates")
    } catch {
      logger.error(
        "Failed to schedule server state updates for activityId: \(activityId, privacy: .public), error: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  @MainActor
  func startGlobalMonitoring() async {
    guard await stateRegistry.startMonitoringIfNeeded() else { return }

    runBackgroundJob(label: "monitorExistingActivities", priority: .utility) { service in
      await service.monitorExistingActivities()
    }

    runBackgroundJob(label: "monitorPushToStartTokens") { service in
      await service.monitorPushToStartTokens()
    }

    runBackgroundJob(label: "monitorAlarmUpdates") { service in
      await service.monitorAlarmUpdates()
    }
  }

  @MainActor
  private func monitorExistingActivities() async {
    for activity in Activity<TrainActivityAttributes>.activities {
      startMonitoringPushTokens(for: activity)
      await rescheduleAlarmIfNeeded(for: activity)
    }
  }

  @MainActor
  func refreshAlarmConfiguration(alarmOffsetMinutes: Int) async {
    let activities = Activity<TrainActivityAttributes>.activities
    let previousOffset = AlarmPreferences.shared.defaultAlarmOffsetMinutes

    // Track rescheduling for each activity
    for activity in activities {
      let previousAlarmTime: Date? = {
        guard let arrivalTime = activity.attributes.destination.estimatedTime else { return nil }
        return arrivalTime.addingTimeInterval(-Double(previousOffset * 60))
      }()

      await TrainAlarmService.shared.cancelArrivalAlarm(
        activityId: activity.id, reason: "rescheduled", wasTriggered: false)
      await stateRegistry.clearAlarmSnapshot(for: activity.id)

      // Track rescheduling if we have the necessary data
      if let arrivalTime = activity.attributes.destination.estimatedTime,
        let previousAlarmTime = previousAlarmTime
      {
        let newAlarmTime = arrivalTime.addingTimeInterval(-Double(alarmOffsetMinutes * 60))
        AnalyticsEventService.shared.trackAlarmRescheduled(
          activityId: activity.id,
          previousOffset: previousOffset,
          newOffset: alarmOffsetMinutes,
          previousAlarmTime: previousAlarmTime,
          newAlarmTime: newAlarmTime
        )
      }
    }

    let alarmEnabled = AlarmPreferences.shared.defaultAlarmEnabled
    guard alarmEnabled else {
      return
    }

    for activity in activities {
      startMonitoringPushTokens(for: activity)

      await scheduleAlarmIfEnabled(
        activityId: activity.id,
        alarmEnabled: alarmEnabled,
        alarmOffsetMinutes: alarmOffsetMinutes,
        arrivalTime: activity.attributes.destination.estimatedTime,
        trainName: activity.attributes.trainName,
        destinationName: activity.attributes.destination.name,
        destinationCode: activity.attributes.destination.code,
        force: true
      )

      await scheduleServerStateUpdates(
        activityId: activity.id,
        trainName: activity.attributes.trainName,
        origin: activity.attributes.from,
        destination: activity.attributes.destination,
        arrivalLeadMinutes: Double(alarmOffsetMinutes)
      )
    }
  }

  private func startMonitoringPushTokens(for activity: Activity<TrainActivityAttributes>) {
    let activityId = activity.id

    runBackgroundJob(label: "monitorPushTokens", priority: .utility) { service in
      await service.monitorPushTokens(activityId: activityId)
    }
  }

  @MainActor
  private func monitorPushTokens(activityId: String) async {
    guard let activity = findActivity(with: activityId) else {
      logger.debug("Activity not found for token monitoring: \(activityId, privacy: .public)")
      return
    }

    logger.debug("Starting push token monitoring for activityId: \(activityId, privacy: .public)")

    // CRITICAL: Register the current token if it exists before monitoring for changes.
    // pushTokenUpdates only emits when the token CHANGES, not the initial value.
    if let currentToken = activity.pushToken {
      let token = currentToken.hexEncodedString()
      logger.debug("Registering initial push token for activityId: \(activityId, privacy: .public)")
      await registerLiveActivityToken(activityId: activityId, token: token)
    }

    // Continue monitoring for token changes
    for await tokenData in activity.pushTokenUpdates {
      guard !Task.isCancelled else {
        logger.debug(
          "Task cancelled, stopping push token monitoring for activityId: \(activityId, privacy: .public)"
        )
        break
      }
      let token = tokenData.hexEncodedString()
      logger.debug("Push token updated for activityId: \(activityId, privacy: .public)")
      await registerLiveActivityToken(activityId: activityId, token: token)
    }
  }

  private func rescheduleAlarmIfNeeded(for activity: Activity<TrainActivityAttributes>) async {
    let alarmEnabled = AlarmPreferences.shared.defaultAlarmEnabled
    guard alarmEnabled else { return }
    guard activity.attributes.destination.estimatedTime != nil else { return }

    let hasAlarm = TrainAlarmService.shared.hasScheduledAlarm(activityId: activity.id)
    guard !hasAlarm else { return }

    await scheduleAlarmIfEnabled(for: activity)
  }

  // MARK: - Token Registration

  private func registerLiveActivityToken(activityId: String, token: String) async {
    await performWithRetry(label: "registerLiveActivityToken") {
      guard let deviceToken = PushRegistrationService.shared.currentToken() else {
        throw TokenRegistrationError.missingDeviceToken
      }

      let _: String = try await self.convexClient.mutation(
        "registrations:registerLiveActivityToken",
        with: [
          "activityId": activityId,
          "token": token,
          "deviceToken": deviceToken,
        ],
        captureTelemetry: true
      )
    }
  }

  private func monitorPushToStartTokens() async {
    logger.debug("Starting push-to-start token monitoring")

    // CRITICAL: Register the current push-to-start token if it exists.
    // pushToStartTokenUpdates only emits when the token CHANGES, not the initial value.
    if let currentToken = Activity<TrainActivityAttributes>.pushToStartToken {
      let token = currentToken.hexEncodedString()
      logger.debug("Registering initial push-to-start token")
      await registerLiveActivityStartToken(token: token)
    }

    // Continue monitoring for token changes
    for await tokenData in Activity<TrainActivityAttributes>.pushToStartTokenUpdates {
      guard !Task.isCancelled else {
        logger.debug("Task cancelled, stopping push-to-start token monitoring")
        break
      }
      let token = tokenData.hexEncodedString()
      logger.debug("Push-to-start token updated")
      await registerLiveActivityStartToken(token: token)
    }
  }

  private func registerLiveActivityStartToken(token: String) async {
    await performWithRetry(label: "registerLiveActivityStartToken") {
      guard let deviceToken = PushRegistrationService.shared.currentToken() else {
        throw TokenRegistrationError.missingDeviceToken
      }

      let _: String = try await self.convexClient.mutation(
        "registrations:registerLiveActivityStartToken",
        with: [
          "deviceToken": deviceToken,
          "token": token,
          "userId": nil,
        ],
        captureTelemetry: true
      )
    }
  }

  private func performWithRetry(
    label: StaticString,
    operation: @escaping () async throws -> Void
  ) async {
    for attempt in 1...Constants.maxRetryAttempts {
      if Task.isCancelled {
        return
      }

      do {
        try await operation()
        return
      } catch is CancellationError {
        return
      } catch {
        guard attempt < Constants.maxRetryAttempts else {
          logger.error(
            "\(label, privacy: .public) exhausted retry attempts: \(error.localizedDescription, privacy: .public)"
          )
          return
        }

        let delayNanoseconds = calculateRetryDelay(for: attempt)
        do {
          try await Task.sleep(nanoseconds: delayNanoseconds)
        } catch is CancellationError {
          return
        } catch {
          logger.error(
            "\(label, privacy: .public) retry sleep failed: \(error.localizedDescription, privacy: .public)"
          )
          return
        }
      }
    }
  }

  func calculateRetryDelay(for attempt: Int) -> UInt64 {
    let exponentialDelay = pow(2.0, Double(attempt)) * Constants.baseRetryDelay
    let baseDelay = UInt64(exponentialDelay * Double(Constants.nanosecondsPerSecond))
    let jitter = UInt64.random(in: 0...Constants.retryJitterNanoseconds)
    return baseDelay + jitter
  }

  private func monitorAlarmUpdates() async {
    logger.debug("Starting alarm updates monitoring")

    for await alarms in AlarmManager.shared.alarmUpdates {
      guard !Task.isCancelled else {
        logger.debug("Task cancelled, stopping alarm updates monitoring")
        break
      }

      for alarm in alarms {
        guard alarm.state == .alerting else { continue }
        guard let activityId = TrainAlarmService.shared.activityId(for: alarm.id) else {
          logger.debug("No activity ID found for alarm: \(alarm.id, privacy: .public)")
          continue
        }

        logger.info("Alarm triggered for activityId: \(activityId, privacy: .public)")
        await handleAlarmTriggered(for: activityId)
      }
    }
  }

  @MainActor
  private func handleAlarmTriggered(for activityId: String) async {
    guard let activity = findActivity(with: activityId) else {
      return
    }

    let destination = activity.attributes.destination
    let offsetMinutes = AlarmPreferences.shared.defaultAlarmOffsetMinutes
    let actualTimeUntilArrivalMinutes: Int? = {
      guard let arrivalTime = destination.estimatedTime else { return nil }
      return Int(max(0, arrivalTime.timeIntervalSinceNow) / 60)
    }()

    AnalyticsEventService.shared.trackAlarmTriggered(
      activityId: activityId,
      trainName: activity.attributes.trainName,
      destinationName: destination.name,
      offsetMinutes: offsetMinutes,
      actualTimeUntilArrivalMinutes: actualTimeUntilArrivalMinutes
    )
    await transitionToPrepareToDropOff(activityId: activityId)
  }
}

// MARK: - Errors

private enum TokenRegistrationError: Error {
  case missingDeviceToken
}
