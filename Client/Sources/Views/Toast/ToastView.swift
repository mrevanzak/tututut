import SwiftUI

// MARK: - Toast Style & Config

enum ToastStyle {
  case success
  case warning
  case error
  case custom(icon: Image, color: Color)

  var icon: Image {
    switch self {
    case .success: return Image(systemName: "checkmark")
    case .warning: return Image(systemName: "exclamationmark.triangle.fill")
    case .error: return Image(systemName: "xmark.circle.fill")
    case .custom(let icon, _): return icon
    }
  }

  var themeColor: Color {
    switch self {
    case .success: return .green
    case .warning: return .orange
    case .error: return .red
    case .custom(_, let color): return color
    }
  }

  var iconColor: Color {
    switch self {
    case .success: return .white
    case .warning: return .black
    case .error: return .white
    case .custom: return .white
    }
  }
}

struct ToastConfig: Equatable {
  let style: ToastStyle
  let message: String
  let duration: TimeInterval

  static func == (lhs: ToastConfig, rhs: ToastConfig) -> Bool {
    lhs.message == rhs.message && lhs.duration == rhs.duration
  }

  static func success(message: String, duration: TimeInterval = 2.0) -> ToastConfig {
    .init(style: .success, message: message, duration: duration)
  }

  static func warning(message: String, duration: TimeInterval = 2.0) -> ToastConfig {
    .init(style: .warning, message: message, duration: duration)
  }

  static func error(message: String, duration: TimeInterval = 2.0) -> ToastConfig {
    .init(style: .error, message: message, duration: duration)
  }

  static func custom(
    message: String, icon: Image, color: Color = .gray, duration: TimeInterval = 2.0
  ) -> ToastConfig {
    .init(style: .custom(icon: icon, color: color), message: message, duration: duration)
  }
}

// MARK: - Toast View

struct ToastView: View {
  let config: ToastConfig
  @Binding var isPresented: Bool

  @Environment(\.colorScheme) private var colorScheme

  // Animation States
  @State private var animationPhase: AnimationPhase = .hidden
  @State private var textOpacity: Double = 0

  private enum AnimationPhase {
    case hidden
    case appearing
    case expanded
    case dismissing
  }

  private var iconSize: CGFloat {
    switch animationPhase {
    case .hidden: return 0
    case .appearing: return 28
    case .expanded: return 28
    case .dismissing: return 28
    }
  }

  private var pillWidth: CGFloat? {
    switch animationPhase {
    case .hidden, .appearing: return 44
    case .expanded, .dismissing: return nil
    }
  }

  var body: some View {
    ZStack {
      if animationPhase != .hidden {
        toastContent
          .transition(
            .asymmetric(
              insertion: .scale(scale: 0.3).combined(with: .opacity).combined(
                with: .move(edge: .top)),
              removal: .scale(scale: 0.8).combined(with: .opacity).combined(with: .move(edge: .top))
            ))
      }
    }
    .onChange(of: isPresented) { _, newValue in
      if newValue {
        presentToast()
      } else {
        dismissToast()
      }
    }
    .onAppear {
      if isPresented {
        presentToast()
      }
    }
  }

  private var toastContent: some View {
    HStack(spacing: 12) {
      // Icon Circle
      iconCircle

      // Text Content - only show when expanded
      if animationPhase == .expanded || animationPhase == .dismissing {
        Text(config.message)
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
          .opacity(textOpacity)
      }
    }
    .padding(.all, 8)
    .padding(.trailing, 4)
    .frame(width: pillWidth, height: 44)
    .background {
      toastBackground
    }
    .clipShape(Capsule())
    .shadow(
      color: Color.black.opacity(colorScheme == .dark ? 0.5 : 0.15),
      radius: 12,
      x: 0,
      y: 6
    )
    .padding(.horizontal, 24)
  }

  private var iconCircle: some View {
    ZStack {
      Circle()
        .fill(config.style.themeColor)
        .frame(width: iconSize, height: iconSize)

      config.style.icon
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(config.style.iconColor)
        .scaleEffect(animationPhase == .appearing ? 0.8 : 1.0)
    }
  }

  @ViewBuilder
  private var toastBackground: some View {
    if colorScheme == .dark {
      Capsule()
        .fill(.ultraThinMaterial)
        .overlay {
          Capsule()
            .fill(Color.black.opacity(0.4))
        }
        .overlay {
          Capsule()
            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        }
    } else {
      Capsule()
        .fill(.regularMaterial)
        .overlay {
          Capsule()
            .fill(Color.white.opacity(0.3))
        }
        .overlay {
          Capsule()
            .strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5)
        }
    }
  }

  // MARK: - Animation Logic

  private func presentToast() {
    // Phase 1: Initial appearance - small circle from top
    withAnimation(.spring(response: 0.35, dampingFraction: 0.68)) {
      animationPhase = .appearing
    }

    // Phase 2: Expand to full pill width with text
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
        animationPhase = .expanded
      }

      // Fade in text slightly after expansion starts
      withAnimation(.easeOut(duration: 0.25).delay(0.1)) {
        textOpacity = 1.0
      }

      // Accessibility announcement
      announceForAccessibility()
    }

    // Phase 3: Auto dismiss after duration
    let totalDisplayTime = config.duration + 0.65  // Account for entrance animation
    DispatchQueue.main.asyncAfter(deadline: .now() + totalDisplayTime) {
      dismissToast()
    }
  }

  private func dismissToast() {
    guard isPresented else { return }

    withAnimation(.easeIn(duration: 0.25)) {
      animationPhase = .dismissing
      textOpacity = 0
    }

    // Complete dismissal
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      withAnimation(.easeIn(duration: 0.2)) {
        animationPhase = .hidden
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        isPresented = false
      }
    }
  }

  private func announceForAccessibility() {
    let announcement: String
    switch config.style {
    case .success:
      announcement = "Success: \(config.message)"
    case .warning:
      announcement = "Warning: \(config.message)"
    case .error:
      announcement = "Error: \(config.message)"
    case .custom:
      announcement = config.message
    }
    UIAccessibility.post(notification: .announcement, argument: announcement)
  }
}
