import AlarmKit
import DebugSwift
import MijickPopups
import UIKit
@preconcurrency import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
  private let notificationCenter = UNUserNotificationCenter.current()
  private let pushRegistrationService = PushRegistrationService.shared
  private let liveActivityService = TrainLiveActivityService.shared
  private let alarmManager = AlarmManager.shared
  
  let debugSwift = DebugSwift()

  func application(
    _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    sceneConfig.delegateClass = PopupSceneDelegate.self
    return sceneConfig
  }

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    notificationCenter.delegate = self

    // Register notification categories
    let tripStart = UNNotificationCategory(
      identifier: "TRIP_START_FALLBACK",
      actions: [],
      intentIdentifiers: [],
      options: [.customDismissAction]
    )
    notificationCenter.setNotificationCategories([tripStart])

    // Register station proximity notification category
    Task { @MainActor in
      StationProximityService.shared.registerNotificationCategory()
      // Location authorization will be requested from onboarding screen
    }

    // Configure telemetry SDKs early
    SentryErrorReporter.configure(
      dsn: Constants.Sentry.dsn,
      environment: Constants.AppMeta.environment,
      release: Constants.AppMeta.version,
      tracesSampleRate: Constants.AppMeta.environment == "production" ? 0.2 : 1.0,
      profilesSampleRate: Constants.AppMeta.environment == "production" ? 0.1 : 1.0
    )
    PostHogAnalytics.configure(
      apiKey: Constants.PostHog.apiKey,
      host: Constants.PostHog.host,
      captureScreenViews: false
    )

    Task {
      // Begin monitoring ActivityKit tokens as early as possible
      await liveActivityService.startGlobalMonitoring()
      // Permission requests will be handled from onboarding screen
    }

    #if DEBUG
      debugSwift.setup()

      DebugSwift.App.shared.customInfo = {
        [
          .init(
            title: "Custom Development Info",
            infos: [.init(title: "Convex URL", subtitle: Constants.Convex.deploymentUrl)])
        ]
      }

      DebugSwift.App.shared.customAction = {
        [
          .init(
            title: "Live Activities Test",
            actions: [
              .init(
                title: "Start Live Activity",
                action: {
                  Task {
                    let _ = try await self.liveActivityService.start(
                      trainName: "Jayabaya",
                      from: TrainStation(
                        name: "Malang", code: "ML",
                        estimatedTime: Date().addingTimeInterval(180)),
                      destination: TrainStation(
                        name: "Pasar Senen", code: "PSE",
                        estimatedTime: Date().addingTimeInterval(240)),
                      //                      seatClass: SeatClass.economy(number: 9),
                      //                      seatNumber: "20C"
                    )
                  }
                }),
              .init(
                title: "Update Live Activity to On Board",
                action: {
                  let activities = self.liveActivityService.getActiveLiveActivities()
                  for activity in activities {
                    Task {
                      await self.liveActivityService.transitionToOnBoard(activityId: activity.id)
                    }
                  }
                }),
              .init(
                title: "Update Live Activity to Prepare to Drop Off",
                action: {
                  let activities = self.liveActivityService.getActiveLiveActivities()
                  for activity in activities {
                    Task {
                      await self.liveActivityService.transitionToPrepareToDropOff(
                        activityId: activity.id)
                    }
                  }
                }),
            ]
          ),
          .init(
            title: "AlarmKit",
            actions: [
              .init(
                title: "Printed out pending alarm",
                action: {
                  let alarms = try? self.alarmManager.alarms

                  guard let alarms = alarms else {
                    print("No alarms")
                    return
                  }

                  for alarm in alarms {
                    print("Alarm: \(String(describing: alarm.countdownDuration?.preAlert))")
                  }
                })
            ]
          ),
        ]
      }

      // Configure memory leak detection
      DebugSwift.Performance.shared.onLeakDetected { leakData in
        print("🔴 Memory leak detected: \(leakData.message)")
      }

      debugSwift.show()
    #endif

    return true
  }

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.hexEncodedString()
    #if DEBUG
      print("APNS device token: \(token)")
      DebugSwift.APNSToken.didRegister(deviceToken: deviceToken)
    #endif
    pushRegistrationService.storeToken(token)

    Task {
      await pushRegistrationService.registerIfNeeded(userId: nil)
    }
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    #if DEBUG
      DebugSwift.APNSToken.didFailToRegister(error: error)
    #endif
    print("Failed to register for remote notifications: \(error.localizedDescription)")
  }

  private func requestNotificationAuthorization() async {
    // Inform DebugSwift that we're about to request permissions
    DebugSwift.APNSToken.willRequestPermissions()

    do {
      let granted = try await notificationCenter.requestAuthorization(options: [
        .alert, .badge, .sound,
      ])

      guard granted else {
        // Inform DebugSwift that permissions were denied
        DebugSwift.APNSToken.didDenyPermissions()
        return
      }

      await MainActor.run {
        UIApplication.shared.registerForRemoteNotifications()
      }
    } catch {
      print("Unable to request notification authorization: \(error.localizedDescription)")
    }
  }
}

extension AppDelegate: @MainActor UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let userInfo = response.notification.request.content.userInfo

    AnalyticsEventService.shared.trackNotificationInteraction(
      identifier: response.notification.request.identifier,
      category: response.notification.request.content.categoryIdentifier,
      action: response.actionIdentifier
    )

    guard
      let deepLinkString = userInfo["deeplink"] as? String,
      let url = URL(string: deepLinkString)
    else {
      return
    }

    await UIApplication.shared.open(url)
  }
}

extension UIWindow {
  open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
    super.motionEnded(motion, with: event)

    #if DEBUG
      if motion == .motionShake {
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
          appDelegate.debugSwift.toggle()
        }
      }
    #endif
  }
}
