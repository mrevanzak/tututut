//
//  ToastView.swift
//  kreta
//
//  Created by AI Assistant
//

import MijickPopups
import SwiftUI

struct Toast: TopPopup {
  let message: String
  let type: ToastMessageType

  var body: some View {
    HStack(spacing: 12) {
      // Icon with animated background
      ZStack {
        Circle()
          .fill(type.backgroundColor.opacity(0.2))
          .frame(width: 32, height: 32)

        Image(systemName: type.iconName)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(type.iconColor)
      }

      // Message text
      Text(message)
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(.primary)
        .multilineTextAlignment(.leading)
        .lineLimit(3)

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(.regularMaterial)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .stroke(type.borderColor.opacity(0.3), lineWidth: 1)
    )
  }

  func configurePopup(config: TopPopupConfig) -> TopPopupConfig {
    config
      .cornerRadius(16)
      .ignoreSafeArea(edges: .top)
      .heightMode(.auto)
      .popupHorizontalPadding(16)
      .popupTopPadding(Screen.safeArea.top + 12)
      .overlayColor(.clear)
      .tapOutsideToDismissPopup(false)
      .backgroundColor(.clear)
  }
}

/// View modifier that adds toast capability to any view
struct WithToastView: ViewModifier {
  func body(content: Content) -> some View {
    content
      .environment(
        \.showToast,
        ShowToastAction { message, type in
          Task {
            if type == .error {
              Dependencies.shared.telemetry.addBreadcrumb(
                message: "User-visible error",
                category: "ui.error",
                data: [
                  "message": message
                ]
              )
            }
            await Toast(message: message, type: type).dismissAfter(2).present()
          }
        })
  }
}

/// Environment action for showing toasts from SwiftUI views
struct ShowToastAction: Sendable {
  let action: @Sendable (String, ToastMessageType) -> Void

  func callAsFunction(
    _ message: String,
    type: ToastMessageType = .info,
  ) {
    action(message, type)
  }
}

/// Environment key for toast actions
private struct ShowToastKey: EnvironmentKey {
  static let defaultValue = ShowToastAction { _, _ in }
}

extension EnvironmentValues {
  var showToast: ShowToastAction {
    get { self[ShowToastKey.self] }
    set { self[ShowToastKey.self] = newValue }
  }
}

extension ShowToastAction {
  static let preview = ShowToastAction { message, type in
    print("🔔 [\(type)] \(message)")
  }
}

extension View {
  /// Add toast capability to any view
  func withToast() -> some View {
    modifier(WithToastView())
  }
}

enum ToastMessageType {
  case error
  case info
  case success

  var haptic: UINotificationFeedbackGenerator.FeedbackType {
    switch self {
    case .error:
      return .error
    case .info:
      return .warning
    case .success:
      return .success
    }
  }

  var iconName: String {
    switch self {
    case .error:
      return "exclamationmark.triangle.fill"
    case .info:
      return "info.circle.fill"
    case .success:
      return "checkmark.circle.fill"
    }
  }

  var iconColor: Color {
    switch self {
    case .error:
      return .red
    case .info:
      return .blue
    case .success:
      return .green
    }
  }

  var backgroundColor: Color {
    switch self {
    case .error:
      return .red
    case .info:
      return .blue
    case .success:
      return .green
    }
  }

  var borderColor: Color {
    switch self {
    case .error:
      return .red
    case .info:
      return .blue
    case .success:
      return .green
    }
  }

  var image: UIImage {
    switch self {
    case .error:
      return UIImage(systemName: "exclamationmark.triangle.fill")!
    case .info:
      return UIImage(systemName: "info.circle.fill")!
    case .success:
      return UIImage(systemName: "checkmark.circle.fill")!
    }
  }
}
