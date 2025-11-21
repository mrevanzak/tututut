import ConvexMobile
import Portal
import SwiftUI

@main
struct KretaApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  @Environment(\.scenePhase) private var scenePhase

  @State var router: Router = .init(level: 0)
  @State private var convexClient = Dependencies.shared.convexClient

  @AppStorage("isAuthenticated") private var isAuthenticated = false

  var body: some Scene {
    WindowGroup {
      PortalContainer {
        NavigationContainer(parentRouter: router) {
          HomeScreen()
        }
      }
      .withToast()
      .environment(\.convexClient, convexClient)
      .onAppear {
        setupToastWindow()
      }
    }
    .onChange(of: scenePhase) { _, newPhase in
      guard newPhase == .active else { return }
      Task {
        await TrainLiveActivityService.shared.refreshInForeground()
      }
    }
  }

  private func setupToastWindow() {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
      return
    }
    Task { @MainActor in
      ToastWindowManager.shared.setup(in: windowScene)
    }
  }
}
