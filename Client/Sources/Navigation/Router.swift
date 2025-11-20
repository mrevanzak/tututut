import OSLog
import SwiftUI

@Observable
final class Router {
  let id = UUID()
  let level: Int

  /// Values presented in the navigation stack
  var navigationStackPath: [PushDestination] = []

  /// Current presented sheet
  var presentingSheet: SheetDestination?

  /// Current presented full screen
  var presentingFullScreen: FullScreenDestination?

  let logger = Logger(subsystem: "kreta", category: "Navigation")

  /// Reference to the parent router to form a hierarchy
  /// Router levels increase for the children
  weak var parent: Router?

  /// A way to track which router is visible/active
  /// Used for deep link resolution
  private(set) var isActive: Bool = false

  init(level: Int) {
    self.level = level
    self.parent = nil

    logger.debug("\(self.debugDescription) initialized")
  }

  deinit {
    logger.debug("\(self.debugDescription) cleared")
  }

  private func resetContent() {
    navigationStackPath = []
    // presentingSheet = nil
    presentingFullScreen = nil
  }
}

// MARK: - Router Management

extension Router {
  func childRouter() -> Router {
    let router = Router(level: level + 1)
    router.parent = self
    return router
  }

  func setActive() {
    logger.debug("\(self.debugDescription): \(#function)")
    parent?.resignActive()
    isActive = true
  }

  func resignActive() {
    logger.debug("\(self.debugDescription): \(#function)")
    isActive = false
  }

  static func previewRouter() -> Router {
    Router(level: 0)
  }
}

// MARK: - Navigation

extension Router {
  func navigate(to destination: Destination) {
    switch destination {

    case let .push(destination):
      push(destination)

    case let .sheet(destination):
      present(sheet: destination)

    case let .fullScreen(destination):
      present(fullScreen: destination)

    case let .action(action):
      execute(action: action)
    }
  }

  func push(_ destination: PushDestination) {
    logger.debug("\(self.debugDescription): \(#function) \(destination)")
    navigationStackPath.append(destination)
  }

  func present(sheet destination: SheetDestination) {
    logger.debug("\(self.debugDescription): \(#function) \(destination)")
    presentingSheet = destination
  }

  func present(fullScreen destination: FullScreenDestination) {
    logger.debug("\(self.debugDescription): \(#function) \(destination)")
    presentingFullScreen = destination
  }

  func execute(action: ActionDestination) {
    logger.debug("\(self.debugDescription): executing action \(action)")
    NotificationCenter.default.post(name: .routerActionRequested, object: action)
  }

  func deepLinkOpen(to destination: Destination) {
    guard isActive else {
      logger.debug("\(self.debugDescription): \(#function) not active")
      return
    }

    logger.debug("\(self.debugDescription): \(#function) \(destination)")
    navigate(to: destination)
  }
}

extension Router: CustomDebugStringConvertible {
  var debugDescription: String {
    "Router[\(shortId) - Level: \(level)]"
  }

  private var shortId: String { String(id.uuidString.split(separator: "-").first ?? "") }
}

extension Notification.Name {
  static let routerActionRequested = Notification.Name("routerActionRequested")
}

