import Foundation

/// Utility for managing alarm preferences with per-activity and global defaults
final class AlarmPreferences: @unchecked Sendable {
  static let shared = AlarmPreferences()

  private let userDefaults = UserDefaults.standard

  // MARK: - Keys
  private enum Keys {
    static let defaultAlarmEnabled = "alarm.defaultEnabled"
    static let defaultAlarmOffsetMinutes = "alarm.defaultOffsetMinutes"
    static let hasCompletedInitialSetup = "alarm.hasCompletedInitialSetup"
    static func alarmEnabled(activityId: String) -> String { "alarm.enabled.\(activityId)" }
    static func alarmOffsetMinutes(activityId: String) -> String {
      "alarm.offsetMinutes.\(activityId)"
    }
  }

  private init() {}

  // MARK: - Global Defaults

  /// Global default for whether alarms are enabled
  var defaultAlarmEnabled: Bool {
    get {
      // If not set, defaults to true
      if userDefaults.object(forKey: Keys.defaultAlarmEnabled) == nil {
        return true
      }
      return userDefaults.bool(forKey: Keys.defaultAlarmEnabled)
    }
    set {
      let previousValue = defaultAlarmEnabled
      guard previousValue != newValue else { return }
      userDefaults.set(newValue, forKey: Keys.defaultAlarmEnabled)
      AnalyticsEventService.shared.trackAlarmPreferenceChanged(
        preferenceType: "enabled",
        previousValue: previousValue,
        newValue: newValue
      )
    }
  }

  /// Global default for alarm offset in minutes
  var defaultAlarmOffsetMinutes: Int {
    get {
      // If not set, defaults to 10 minutes
      let value = userDefaults.integer(forKey: Keys.defaultAlarmOffsetMinutes)
      return value > 0 ? value : 10
    }
    set {
      let previousValue = defaultAlarmOffsetMinutes
      guard previousValue != newValue else { return }
      userDefaults.set(newValue, forKey: Keys.defaultAlarmOffsetMinutes)
      AnalyticsEventService.shared.trackAlarmPreferenceChanged(
        preferenceType: "offset_minutes",
        previousValue: previousValue,
        newValue: newValue
      )
    }
  }

  /// Whether the user has completed the initial alarm setup
  var hasCompletedInitialSetup: Bool {
    get {
      userDefaults.bool(forKey: Keys.hasCompletedInitialSetup)
    }
    set {
      userDefaults.set(newValue, forKey: Keys.hasCompletedInitialSetup)
    }
  }

  /// Mark the initial alarm setup as complete
  func markInitialSetupComplete() {
    hasCompletedInitialSetup = true
  }

  /// Clear all global defaults (resets to hardcoded defaults)
  func clearGlobalDefaults() {
    userDefaults.removeObject(forKey: Keys.defaultAlarmEnabled)
    userDefaults.removeObject(forKey: Keys.defaultAlarmOffsetMinutes)
    userDefaults.removeObject(forKey: Keys.hasCompletedInitialSetup)
  }
}
