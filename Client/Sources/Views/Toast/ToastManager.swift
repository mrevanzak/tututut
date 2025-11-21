//
//  ToastManager.swift
//  kreta
//
//  Created by AI Assistant
//

import SwiftUI

@MainActor
@Observable
final class ToastManager {
  static let shared = ToastManager()

  var currentToast: ToastConfig?
  private var queue: [ToastConfig] = []
  private var isShowing = false

  func show(config: ToastConfig) {
    if isShowing {
      queue.append(config)
    } else {
      showToast(config)
    }
  }

  // Convenience helpers
  func show(message: String, style: ToastStyle, duration: TimeInterval = 2.0) {
    let config = ToastConfig(style: style, message: message, duration: duration)
    show(config: config)
  }

  private func showToast(_ config: ToastConfig) {
    isShowing = true
    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
      currentToast = config
    }

    // Haptic feedback
    let generator = UINotificationFeedbackGenerator()
    switch config.style {
    case .success, .custom: generator.notificationOccurred(.success)
    case .warning: generator.notificationOccurred(.warning)
    case .error: generator.notificationOccurred(.error)
    }

    // Auto dismiss is handled by ToastView.
    // We wait for the view to update the binding to false, which calls dismiss().
  }

  func dismiss() async {
    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
      currentToast = nil
    }

    try? await Task.sleep(nanoseconds: 300_000_000)  // Wait for animation

    isShowing = false
    if !queue.isEmpty {
      let next = queue.removeFirst()
      showToast(next)
    }
  }
}

// MARK: - Environment & Helpers

struct ShowToastAction: Sendable {
  let action: @Sendable (String, ToastStyle) -> Void

  func callAsFunction(_ message: String, type: ToastStyle = .success) {
    action(message, type)
  }
}

private struct ShowToastKey: EnvironmentKey {
  static let defaultValue = ShowToastAction { _, _ in }
}

extension EnvironmentValues {
  var showToast: ShowToastAction {
    get { self[ShowToastKey.self] }
    set { self[ShowToastKey.self] = newValue }
  }
}

extension View {
  func withToast() -> some View {
    self.environment(
      \.showToast,
      ShowToastAction { message, style in
        Task { @MainActor in
          ToastManager.shared.show(message: message, style: style)
        }
      })
  }
}
