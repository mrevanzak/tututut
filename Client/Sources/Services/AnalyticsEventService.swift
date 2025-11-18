import Foundation

// MARK: - AnalyticsEventService

final class AnalyticsEventService: @unchecked Sendable {
  static let shared = AnalyticsEventService()

  private let telemetry: Telemetry
  private let userDefaults: UserDefaults
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  // Keep last N journeys for round-trip detection
  private let maxStoredJourneys = 10
  private let roundTripWindowDays: Int = 7

  private enum StorageKeys {
    static let journeyHistory = "analytics.journeyHistory"
  }

  private init(
    telemetry: Telemetry = Dependencies.shared.telemetry,
    userDefaults: UserDefaults = .standard
  ) {
    self.telemetry = telemetry
    self.userDefaults = userDefaults
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  // MARK: - Models

  struct JourneyRecord: Codable, Equatable {
    let trainId: String
    let fromStationId: String
    let toStationId: String
    let completedAt: Date

    var directionKey: String { "\(fromStationId)->\(toStationId)" }
  }

  // MARK: - Core Journey Events

  func trackJourneyStarted(
    trainId: String,
    trainName: String,
    from: Station,
    to: Station,
    userSelectedDeparture: Date,
    userSelectedArrival: Date,
    hasAlarmEnabled: Bool
  ) {
    let now = Date()
    let durationMinutes = Int(userSelectedArrival.timeIntervalSince(userSelectedDeparture) / 60)
    let timeUntilDepartureMinutes = Int(max(0, userSelectedDeparture.timeIntervalSince(now)) / 60)

    telemetry.track(
      event: "journey_started",
      properties: [
        "train_id": trainId,
        "train_name": trainName,
        "from_station_id": from.id ?? from.code,
        "from_station_name": from.name,
        "to_station_id": to.id ?? to.code,
        "to_station_name": to.name,
        "departure_time": iso8601String(userSelectedDeparture),
        "arrival_time": iso8601String(userSelectedArrival),
        "journey_duration_minutes": durationMinutes,
        "time_until_departure_minutes": timeUntilDepartureMinutes,
        "has_alarm_enabled": hasAlarmEnabled,
      ]
    )
  }

  func trackJourneyCancelled(trainId: String, reason: String?, context: [String: Any] = [:]) {
    var props: [String: Any] = [
      "train_id": trainId
    ]
    if let reason { props["reason"] = reason }
    for (k, v) in context { props[k] = v }
    telemetry.track(event: "journey_cancelled", properties: props)
  }

  /// Track completion with full context (preferred).
  func trackJourneyCompleted(
    trainId: String,
    from: Station,
    to: Station,
    userSelectedDeparture: Date,
    completionType: String,  // "arrival_screen" | "scheduled_arrival"
    actualArrival: Date,
    wasTrackedUntilArrival: Bool
  ) {
    let duration = Int(max(0, actualArrival.timeIntervalSince(userSelectedDeparture)) / 60)

    telemetry.track(
      event: "journey_completed",
      properties: [
        "train_id": trainId,
        "from_station_id": from.id ?? from.code,
        "to_station_id": to.id ?? to.code,
        "journey_duration_actual_minutes": duration,
        "completion_type": completionType,
        "was_tracked_until_arrival": wasTrackedUntilArrival,
        "completed_at": iso8601String(actualArrival),
      ]
    )

    // Persist and evaluate round-trip
    let record = JourneyRecord(
      trainId: trainId,
      fromStationId: from.id ?? from.code,
      toStationId: to.id ?? to.code,
      completedAt: actualArrival
    )
    appendJourneyRecord(record)
    trackRoundTripIfApplicable(currentJourney: record)
  }

  /// Minimal completion tracking (e.g., from arrival screen without full context).
  func trackJourneyCompletedMinimal(
    destinationCode: String,
    destinationName: String,
    completionType: String = "arrival_screen"
  ) {
    telemetry.track(
      event: "journey_completed",
      properties: [
        "to_station_id": destinationCode,
        "to_station_name": destinationName,
        "completion_type": completionType,
        "completed_at": iso8601String(Date()),
      ]
    )
  }

  // MARK: - Round Trip

  func trackRoundTripIfApplicable(currentJourney: JourneyRecord) {
    let history = loadJourneyHistory()
    guard !history.isEmpty else { return }
    let windowStart =
      Calendar.current.date(
        byAdding: .day, value: -roundTripWindowDays, to: currentJourney.completedAt)
      ?? currentJourney.completedAt

    // Find last journey in the window
    let prior =
      history
      .filter { $0.completedAt >= windowStart && $0.completedAt <= currentJourney.completedAt }
      .sorted { $0.completedAt > $1.completedAt }
      .first

    guard let previous = prior else { return }

    let isReverseDirection =
      previous.fromStationId == currentJourney.toStationId
      && previous.toStationId == currentJourney.fromStationId

    let daysBetween =
      Calendar.current.dateComponents(
        [.day], from: previous.completedAt, to: currentJourney.completedAt
      ).day ?? 0

    telemetry.track(
      event: "round_trip_completed",
      properties: [
        "days_between_trips": daysBetween,
        "is_reverse_direction": isReverseDirection,
        "previous_journey_id":
          "\(previous.fromStationId)->\(previous.toStationId)@\(iso8601String(previous.completedAt))",
      ]
    )
  }

  #if DEBUG
    /// Test helper to evaluate round-trip detection without side effects.
    func _test_evaluateRoundTrip(
      currentJourney: JourneyRecord,
      history: [JourneyRecord]
    ) -> (isRoundTrip: Bool, isReverseDirection: Bool, daysBetween: Int)? {
      guard !history.isEmpty else { return nil }
      let windowStart =
        Calendar.current.date(
          byAdding: .day, value: -roundTripWindowDays, to: currentJourney.completedAt)
        ?? currentJourney.completedAt
      let prior =
        history
        .filter { $0.completedAt >= windowStart && $0.completedAt <= currentJourney.completedAt }
        .sorted { $0.completedAt > $1.completedAt }
        .first
      guard let previous = prior else { return nil }
      let isReverseDirection =
        previous.fromStationId == currentJourney.toStationId
        && previous.toStationId == currentJourney.fromStationId
      let daysBetween =
        Calendar.current.dateComponents(
          [.day], from: previous.completedAt, to: currentJourney.completedAt
        ).day ?? 0
      return (true, isReverseDirection, daysBetween)
    }
  #endif

  // MARK: - Engagement Events

  func trackTrainSearchInitiated() {
    telemetry.track(event: "train_search_initiated", properties: nil)
  }

  func trackStationSelected(station: Station, selectionType: String) {
    telemetry.track(
      event: "station_selected",
      properties: [
        "station_id": station.id ?? station.code,
        "station_name": station.name,
        "selection_type": selectionType,
      ]
    )
  }

  func trackTrainSelected(item: JourneyService.AvailableTrainItem) {
    telemetry.track(
      event: "train_selected",
      properties: [
        "train_id": item.trainId,
        "train_code": item.code,
        "train_name": item.name,
        "from_station_id": item.fromStationId,
        "to_station_id": item.toStationId,
        "departure_time": iso8601String(item.segmentDeparture),
        "arrival_time": iso8601String(item.segmentArrival),
      ]
    )
  }

  func trackArrivalConfirmed(stationCode: String, stationName: String) {
    telemetry.track(
      event: "arrival_confirmed",
      properties: [
        "station_code": stationCode,
        "station_name": stationName,
      ]
    )
  }

  // MARK: - Live Activity / Alarm

  func trackLiveActivityStateChanged(activityId: String, state: String, trainName: String) {
    telemetry.track(
      event: "live_activity_state_changed",
      properties: [
        "activity_id": activityId,
        "state": state,
        "train_name": trainName,
      ]
    )
  }

  func trackAlarmScheduled(
    activityId: String,
    arrivalTime: Date,
    offsetMinutes: Int,
    destinationCode: String,
    trainName: String? = nil,
    destinationName: String? = nil,
    alarmTime: Date? = nil
  ) {
    var properties: [String: Any] = [
      "activity_id": activityId,
      "arrival_time": iso8601String(arrivalTime),
      "alarm_offset_minutes": offsetMinutes,
      "destination_code": destinationCode,
    ]

    if let trainName {
      properties["train_name"] = trainName
    }
    if let destinationName {
      properties["destination_name"] = destinationName
    }
    if let alarmTime {
      properties["alarm_time"] = iso8601String(alarmTime)
      let timeUntilAlarmMinutes = Int(max(0, alarmTime.timeIntervalSinceNow) / 60)
      properties["time_until_alarm_minutes"] = timeUntilAlarmMinutes
    }

    telemetry.track(
      event: "alarm_scheduled",
      properties: properties
    )
  }

  func trackAlarmTriggered(
    activityId: String,
    trainName: String? = nil,
    destinationName: String? = nil,
    offsetMinutes: Int? = nil,
    actualTimeUntilArrivalMinutes: Int? = nil
  ) {
    var properties: [String: Any] = [
      "activity_id": activityId,
      "triggered_at": iso8601String(Date()),
    ]

    if let trainName {
      properties["train_name"] = trainName
    }
    if let destinationName {
      properties["destination_name"] = destinationName
    }
    if let offsetMinutes {
      properties["offset_minutes"] = offsetMinutes
    }
    if let actualTimeUntilArrivalMinutes {
      properties["actual_time_until_arrival_minutes"] = actualTimeUntilArrivalMinutes
    }

    telemetry.track(
      event: "alarm_triggered",
      properties: properties
    )
  }

  func trackAlarmConfigured(
    offsetMinutes: Int,
    isValid: Bool,
    validationFailureReason: String?,
    isInitialSetup: Bool? = nil,
    previousOffsetMinutes: Int? = nil,
    journeyDurationMinutes: Int? = nil,
    validationWarnings: [String]? = nil
  ) {
    var properties: [String: Any] = [
      "alarm_offset_minutes": offsetMinutes,
      "is_valid": isValid,
      "configured_at": iso8601String(Date()),
    ]

    if let reason = validationFailureReason {
      properties["validation_failure_reason"] = reason
    }
    if let isInitialSetup {
      properties["is_initial_setup"] = isInitialSetup
    }
    if let previousOffsetMinutes {
      properties["previous_offset_minutes"] = previousOffsetMinutes
    }
    if let journeyDurationMinutes {
      properties["journey_duration_minutes"] = journeyDurationMinutes
    }
    if let validationWarnings {
      properties["validation_warnings"] = validationWarnings
    }

    telemetry.track(
      event: "alarm_configured",
      properties: properties
    )
  }

  // MARK: - Alarm Authorization Events

  func trackAlarmAuthorizationRequested(previousState: String) {
    telemetry.track(
      event: "alarm_authorization_requested",
      properties: [
        "requested_at": iso8601String(Date()),
        "previous_state": previousState,
      ]
    )
  }

  func trackAlarmAuthorizationGranted(isFirstTime: Bool) {
    telemetry.track(
      event: "alarm_authorization_granted",
      properties: [
        "granted_at": iso8601String(Date()),
        "is_first_time": isFirstTime,
      ]
    )
  }

  func trackAlarmAuthorizationDenied(wasPreviouslyDenied: Bool) {
    telemetry.track(
      event: "alarm_authorization_denied",
      properties: [
        "denied_at": iso8601String(Date()),
        "was_previously_denied": wasPreviouslyDenied,
      ]
    )
  }

  // MARK: - Alarm Lifecycle Events

  func trackAlarmSchedulingFailed(
    activityId: String,
    errorReason: String,
    arrivalTime: Date,
    offsetMinutes: Int
  ) {
    telemetry.track(
      event: "alarm_scheduling_failed",
      properties: [
        "activity_id": activityId,
        "error_reason": errorReason,
        "arrival_time": iso8601String(arrivalTime),
        "offset_minutes": offsetMinutes,
        "attempted_at": iso8601String(Date()),
      ]
    )
  }

  func trackAlarmCancelled(
    activityId: String,
    reason: String,
    wasTriggered: Bool,
    timeUntilAlarmMinutes: Int? = nil
  ) {
    var properties: [String: Any] = [
      "activity_id": activityId,
      "cancellation_reason": reason,
      "was_triggered": wasTriggered,
    ]

    if let timeUntilAlarmMinutes {
      properties["time_until_alarm_minutes"] = timeUntilAlarmMinutes
    }

    telemetry.track(
      event: "alarm_cancelled",
      properties: properties
    )
  }

  func trackAlarmRescheduled(
    activityId: String,
    previousOffset: Int,
    newOffset: Int,
    previousAlarmTime: Date,
    newAlarmTime: Date
  ) {
    telemetry.track(
      event: "alarm_rescheduled",
      properties: [
        "activity_id": activityId,
        "previous_offset_minutes": previousOffset,
        "new_offset_minutes": newOffset,
        "previous_alarm_time": iso8601String(previousAlarmTime),
        "new_alarm_time": iso8601String(newAlarmTime),
      ]
    )
  }

  // MARK: - Alarm Interaction Events

  func trackAlarmDismissed(activityId: String, timeSinceTriggeredSeconds: Int) {
    telemetry.track(
      event: "alarm_dismissed",
      properties: [
        "activity_id": activityId,
        "dismissed_at": iso8601String(Date()),
        "time_since_triggered_seconds": timeSinceTriggeredSeconds,
      ]
    )
  }

  func trackAlarmInteracted(activityId: String, actionType: String) {
    telemetry.track(
      event: "alarm_interacted",
      properties: [
        "activity_id": activityId,
        "action_type": actionType,
        "interacted_at": iso8601String(Date()),
      ]
    )
  }

  // MARK: - Alarm Preference Events

  func trackAlarmPreferenceChanged(preferenceType: String, previousValue: Any, newValue: Any) {
    telemetry.track(
      event: "alarm_preference_changed",
      properties: [
        "preference_type": preferenceType,
        "previous_value": previousValue,
        "new_value": newValue,
        "changed_at": iso8601String(Date()),
      ]
    )
  }

  // MARK: - Technical

  func trackDeepLinkOpened(urlString: String, params: [String: String]) {
    var props: [String: Any] = ["url": urlString]
    for (k, v) in params { props[k] = v }
    telemetry.track(event: "deep_link_opened", properties: props)
  }

  func trackNotificationInteraction(identifier: String?, category: String?, action: String?) {
    telemetry.track(
      event: "notification_interaction",
      properties: [
        "notification_identifier": identifier as Any,
        "category": category as Any,
        "action": action as Any,
      ]
    )
  }

  // MARK: - History Storage

  private func loadJourneyHistory() -> [JourneyRecord] {
    guard let data = userDefaults.data(forKey: StorageKeys.journeyHistory) else { return [] }
    if let decoded = try? decoder.decode([JourneyRecord].self, from: data) { return decoded }
    return []
  }

  private func saveJourneyHistory(_ history: [JourneyRecord]) {
    if let data = try? encoder.encode(history) {
      userDefaults.set(data, forKey: StorageKeys.journeyHistory)
    }
  }

  private func appendJourneyRecord(_ record: JourneyRecord) {
    var history = loadJourneyHistory()
    history.insert(record, at: 0)
    if history.count > maxStoredJourneys { history = Array(history.prefix(maxStoredJourneys)) }
    saveJourneyHistory(history)
  }

  // MARK: - Helpers

  private func iso8601String(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }
}
