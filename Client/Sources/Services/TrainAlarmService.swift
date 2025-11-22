import ActivityKit
import AlarmKit
import Foundation
import OSLog

// MARK: - Metadata

/// Metadata for train arrival alarms
struct TrainAlarmMetadata: AlarmMetadata, Codable, Hashable, Sendable {
  let activityId: String
  let trainName: String
  let destinationName: String
  let destinationCode: String
  let offsetMinutes: Int
}

// MARK: - TrainAlarmService

/// Service for managing arrival alarms using AlarmKit
final class TrainAlarmService: @unchecked Sendable {
  static let shared = TrainAlarmService()

  // MARK: - Constants

  private enum Constants {
    static let defaultOffsetMinutes = 10
    static let secondsPerMinute = 60
  }

  // MARK: - Properties

  private let alarmManager = AlarmManager.shared
  private let lockQueue = DispatchQueue(label: "com.kreta.alarmService.queue")
  private let logger = Logger(subsystem: "kreta", category: "TrainAlarmService")
  private var _activeAlarmIds: [String: Alarm.ID] = [:]

  private var activeAlarmIds: [String: Alarm.ID] {
    get {
      lockQueue.sync { _activeAlarmIds }
    }
    set {
      lockQueue.sync { _activeAlarmIds = newValue }
    }
  }

  private init() {}

  // MARK: - Authorization

  /// Request authorization for AlarmKit
  func requestAuthorization() async -> Bool {
    let currentState = alarmManager.authorizationState
    logger.info("AlarmKit authorization state: \(String(describing: currentState))")

    let previousStateString = authorizationStateString(currentState)

    switch currentState {
    case .notDetermined:
      AnalyticsEventService.shared.trackAlarmAuthorizationRequested(
        previousState: previousStateString)
      return await requestNewAuthorization(isFirstTime: true)
    case .denied:
      logger.warning("AlarmKit authorization was previously denied")
      AnalyticsEventService.shared.trackAlarmAuthorizationDenied(wasPreviouslyDenied: true)
      return false
    case .authorized:
      logger.info("AlarmKit authorization already granted")
      return true
    @unknown default:
      logger.warning("Unknown AlarmKit authorization state: \(String(describing: currentState))")
      return false
    }
  }

  private func requestNewAuthorization(isFirstTime: Bool) async -> Bool {
    do {
      logger.info("Requesting AlarmKit authorization")
      let state = try await alarmManager.requestAuthorization()
      logger.info("AlarmKit authorization result: \(String(describing: state))")

      if state == .authorized {
        AnalyticsEventService.shared.trackAlarmAuthorizationGranted(isFirstTime: isFirstTime)
      } else {
        AnalyticsEventService.shared.trackAlarmAuthorizationDenied(wasPreviouslyDenied: false)
      }

      return state == .authorized
    } catch {
      logger.error("Error requesting AlarmKit authorization: \(error.localizedDescription)")
      AnalyticsEventService.shared.trackAlarmAuthorizationDenied(wasPreviouslyDenied: false)
      return false
    }
  }

  private func authorizationStateString(_ state: AlarmManager.AuthorizationState) -> String {
    switch state {
    case .notDetermined:
      return "notDetermined"
    case .denied:
      return "denied"
    case .authorized:
      return "authorized"
    @unknown default:
      return "unknown"
    }
  }

  // MARK: - Alarm Scheduling

  /// Schedule an arrival alarm for a Live Activity
  /// - Parameters:
  ///   - activityId: The ID of the Live Activity
  ///   - arrivalTime: The estimated arrival time at destination
  ///   - offsetMinutes: Minutes before arrival to trigger alarm (default: 10)
  ///   - trainName: Name of the train for notification content
  ///   - destinationName: Name of destination station
  ///   - destinationCode: Station code (e.g., "PSE")
  func scheduleArrivalAlarm(
    activityId: String,
    arrivalTime: Date,
    offsetMinutes: Int = Constants.defaultOffsetMinutes,
    trainName: String,
    destinationName: String,
    destinationCode: String
  ) async throws {
    guard await requestAuthorization() else {
      throw TrainAlarmError.schedulingFailed("AlarmKit authorization not granted")
    }

    let alarmTime = calculateAlarmTime(arrivalTime: arrivalTime, offsetMinutes: offsetMinutes)
    guard isAlarmTimeValid(alarmTime) else {
      logger.warning("Alarm time \(alarmTime) is in the past, skipping")
      return
    }

    logAlarmDetails(
      activityId: activityId,
      arrivalTime: arrivalTime,
      alarmTime: alarmTime,
      offsetMinutes: offsetMinutes
    )

    await cancelArrivalAlarm(activityId: activityId)

    let alarmId = createAlarmId(from: activityId)
    let metadata = createMetadata(
      activityId: activityId,
      trainName: trainName,
      destinationName: destinationName,
      destinationCode: destinationCode,
      offsetMinutes: offsetMinutes
    )
    let configuration = createAlarmConfiguration(
      alarmTime: alarmTime,
      metadata: metadata
    )

    try await scheduleAlarm(
      id: alarmId,
      configuration: configuration,
      activityId: activityId,
      metadata: metadata,
      arrivalTime: arrivalTime
    )
  }

  private func calculateAlarmTime(arrivalTime: Date, offsetMinutes: Int) -> Date {
    let offsetInSeconds = Double(offsetMinutes * Constants.secondsPerMinute)
    return arrivalTime.addingTimeInterval(-offsetInSeconds)
  }

  private func isAlarmTimeValid(_ alarmTime: Date) -> Bool {
    alarmTime > Date()
  }

  private func logAlarmDetails(
    activityId: String,
    arrivalTime: Date,
    alarmTime: Date,
    offsetMinutes: Int
  ) {
    logger.info("Scheduling alarm for activity \(activityId)")
    logger.debug("Arrival time: \(arrivalTime, privacy: .public)")
    logger.debug("Alarm time (arrival - \(offsetMinutes)min): \(alarmTime, privacy: .public)")
    logger.debug("Current time: \(Date(), privacy: .public)")
  }

  private func createAlarmId(from activityId: String) -> Alarm.ID {
    Alarm.ID(uuidString: activityId) ?? UUID()
  }

  private func createMetadata(
    activityId: String,
    trainName: String,
    destinationName: String,
    destinationCode: String,
    offsetMinutes: Int
  ) -> TrainAlarmMetadata {
    TrainAlarmMetadata(
      activityId: activityId,
      trainName: trainName,
      destinationName: destinationName,
      destinationCode: destinationCode,
      offsetMinutes: offsetMinutes
    )
  }

  private func createAlarmConfiguration(
    alarmTime: Date,
    metadata: TrainAlarmMetadata
  ) -> AlarmManager.AlarmConfiguration<TrainAlarmMetadata> {
    let stopButton = AlarmButton(
      text: LocalizedStringResource("Siap"),
      textColor: .white,
      systemImageName: "stop.circle.fill"
    )

    let alert = AlarmPresentation.Alert(
      title: LocalizedStringResource("Segera Turun!"),
      stopButton: stopButton,
      secondaryButton: nil,
      secondaryButtonBehavior: nil
    )

    let attributes = AlarmAttributes<TrainAlarmMetadata>(
      presentation: AlarmPresentation(alert: alert),
      metadata: metadata,
      tintColor: .highlight
    )

    return AlarmManager.AlarmConfiguration(
      countdownDuration: nil,
      schedule: Alarm.Schedule.fixed(alarmTime),
      attributes: attributes,
      stopIntent: nil,
      secondaryIntent: nil,
      sound: .default
    )
  }

  private func scheduleAlarm(
    id: Alarm.ID,
    configuration: AlarmManager.AlarmConfiguration<TrainAlarmMetadata>,
    activityId: String,
    metadata: TrainAlarmMetadata,
    arrivalTime: Date
  ) async throws {
    do {
      logger.info("Attempting to schedule AlarmKit alarm")
      let scheduledAlarm = try await alarmManager.schedule(id: id, configuration: configuration)

      lockQueue.sync {
        _activeAlarmIds[activityId] = id
      }

      logger.info(
        "Successfully scheduled AlarmKit alarm: activityId=\(activityId) alarmId=\(String(describing: id))"
      )
      logger.debug("Alarm state: \(String(describing: scheduledAlarm.state))")
    } catch {
      logger.error("Failed to schedule AlarmKit alarm: \(error.localizedDescription)")
      AnalyticsEventService.shared.trackAlarmSchedulingFailed(
        activityId: activityId,
        errorReason: error.localizedDescription,
        arrivalTime: arrivalTime,
        offsetMinutes: metadata.offsetMinutes
      )
      throw TrainAlarmError.schedulingFailed(error.localizedDescription)
    }
  }

  // MARK: - Alarm Cancellation

  /// Cancel the arrival alarm for a specific Live Activity
  func cancelArrivalAlarm(
    activityId: String, reason: String = "journey_ended", wasTriggered: Bool = false
  ) async {
    let alarmId = lockQueue.sync { _activeAlarmIds[activityId] }
    guard let alarmId = alarmId else { return }

    // Calculate time until alarm if we can get the alarm info
    var timeUntilAlarmMinutes: Int? = nil
    if let alarm = try? alarmManager.alarms.first(where: { $0.id == alarmId }),
      case .fixed(let scheduledTime) = alarm.schedule
    {
      let minutes = Int(max(0, scheduledTime.timeIntervalSinceNow) / 60)
      timeUntilAlarmMinutes = minutes > 0 ? minutes : nil
    }

    do {
      try alarmManager.cancel(id: alarmId)
      _ = lockQueue.sync { _activeAlarmIds.removeValue(forKey: activityId) }
      logger.info("Cancelled AlarmKit alarm for activity \(activityId)")

      AnalyticsEventService.shared.trackAlarmCancelled(
        activityId: activityId,
        reason: reason,
        wasTriggered: wasTriggered,
        timeUntilAlarmMinutes: timeUntilAlarmMinutes
      )
    } catch {
      logger.warning("Failed to cancel alarm: \(error.localizedDescription)")
    }
  }

  /// Cancel all active arrival alarms
  func cancelAllAlarms(reason: String = "manual_cancel") async {
    let alarmIds = lockQueue.sync { Array(_activeAlarmIds.values) }
    let activityIds = lockQueue.sync { Array(_activeAlarmIds.keys) }
    let count = alarmIds.count

    for alarmId in alarmIds {
      do {
        try alarmManager.cancel(id: alarmId)
      } catch {
        logger.warning("Failed to cancel alarm: \(error.localizedDescription)")
      }
    }

    lockQueue.sync {
      _activeAlarmIds.removeAll()
    }

    logger.info("Cancelled all \(count) AlarmKit alarms")

    // Track cancellation for each activity
    for activityId in activityIds {
      AnalyticsEventService.shared.trackAlarmCancelled(
        activityId: activityId,
        reason: reason,
        wasTriggered: false,
        timeUntilAlarmMinutes: nil
      )
    }
  }

  // MARK: - Alarm Queries

  /// Check if an alarm is scheduled for a specific activity
  func hasScheduledAlarm(activityId: String) -> Bool {
    lockQueue.sync { _activeAlarmIds[activityId] != nil }
  }

  /// Get the activity ID for a given alarm ID
  func activityId(for alarmId: Alarm.ID) -> String? {
    lockQueue.sync {
      for (activityId, storedAlarmId) in _activeAlarmIds where storedAlarmId == alarmId {
        return activityId
      }
      return nil
    }
  }

}

// MARK: - Errors

/// Errors thrown by TrainAlarmService
enum TrainAlarmError: Error, LocalizedError {
  case schedulingFailed(String)
  case invalidAlarmTime

  var errorDescription: String? {
    switch self {
    case .schedulingFailed(let reason):
      return "Failed to schedule arrival alarm: \(reason)"
    case .invalidAlarmTime:
      return "Alarm time must be in the future"
    }
  }
}
