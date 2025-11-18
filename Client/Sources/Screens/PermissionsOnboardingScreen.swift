import AlarmKit
import CoreLocation
import SwiftUI
import UserNotifications

/// Onboarding screen with feature introduction and permission requests
struct PermissionsOnboardingScreen: View {
  @Environment(\.dismiss) private var dismiss

  @State private var currentPage = 0
  @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
  @State private var alarmStatus: AlarmManager.AuthorizationState = .notDetermined
  @State private var locationStatus: CLAuthorizationStatus = .notDetermined

  @State private var isRequestingNotification = false
  @State private var isRequestingAlarm = false
  @State private var isRequestingLocation = false

  // Animation states
  @State private var isAnimatingIcon = false
  @State private var isAnimatingCard = false
  @State private var confettiCounter = 0
  @Namespace private var ctaNamespace

  private let permissionService = PermissionRequestService.shared
  private let totalPages = 5
  private let ctaId = "onboardingPrimaryCTA"

  var body: some View {
    ZStack {
      // Atmospheric background
      atmosphericBackground

      // Content
      TabView(selection: $currentPage) {
        welcomePage.tag(0)
        locationPermissionPage.tag(1)
        alarmPermissionPage.tag(2)
        notificationPermissionPage.tag(3)
        finalPage.tag(4)
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .animation(.spring(response: 0.4, dampingFraction: 0.85), value: currentPage)
      .onChange(of: currentPage) { _, _ in
        // Trigger animations when page changes
        isAnimatingIcon = false
        isAnimatingCard = false

        // Delay to allow page transition to start
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
          withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            isAnimatingIcon = true
          }
          withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.05)) {
            isAnimatingCard = true
          }

          // Confetti for final page
          if currentPage == 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
              confettiCounter += 1
            }
          }
        }
      }

      // Custom page indicators and controls
      VStack {
        Spacer()

        controlsOverlay
          .padding(.horizontal, 24)
          .padding(.bottom, 48)
      }
    }
    .ignoresSafeArea()
    .task {
      await refreshPermissionStatuses()
    }
    .onAppear {
      // Initial animation for first page
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
          isAnimatingIcon = true
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.05)) {
          isAnimatingCard = true
        }
      }
    }
  }

  // MARK: - Atmospheric Background

  private var atmosphericBackground: some View {
    ZStack {
      // Base gradient
      LinearGradient(
        colors: [
          Color.highlight.opacity(0.15),
          Color.backgroundPrimary,
          Color.backgroundPrimary,
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      // Subtle noise texture effect
      Color.black.opacity(0.02)
    }
    .ignoresSafeArea()
  }

  // MARK: - Welcome Page

  private var welcomePage: some View {
    VStack(spacing: 0) {
      Spacer()

      Image(.logo)
        .resizable()
        .scaledToFit()
        .frame(width: 100, height: 100)
        .padding(.bottom, 48)

      VStack(spacing: 16) {
        Text("Selamat Datang di Kreta")
          .font(.largeTitle.weight(.bold))
          .multilineTextAlignment(.center)

        Text("Lacak perjalanan kereta secara real-time\ndan jangan pernah lewatkan stasiun lagi")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineSpacing(4)
      }
      .padding(.horizontal, 32)

      Spacer()
      Spacer()
    }
  }

  // MARK: - Location Permission Page

  private var locationPermissionPage: some View {
    VStack(spacing: 0) {
      // Page counter
      HStack {
        Spacer()
        Text("1/3")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .padding(.top, 60)
          .padding(.trailing, 24)
      }
      .ignoresSafeArea(.container, edges: .top)

      Spacer()

      Image(.location)
        .resizable()
        .scaledToFit()
        .frame(width: 100, height: 100)
        .padding(.bottom, 48)
        .opacity(isAnimatingIcon ? 1.0 : 0.0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05), value: isAnimatingIcon)

      VStack(spacing: 16) {
        Text("Akses Lokasi")
          .font(.largeTitle.weight(.bold))
          .multilineTextAlignment(.center)
          .opacity(isAnimatingCard ? 1.0 : 0.0)

        Text("Agar kami bisa memandu berdasarkan\nlokasi kamu.")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineSpacing(4)
          .opacity(isAnimatingCard ? 1.0 : 0.0)
      }
      .padding(.horizontal, 32)

      Spacer()
      Spacer()
    }
  }

  // MARK: - Alarm Permission Page

  private var alarmPermissionPage: some View {
    VStack(spacing: 0) {
      // Page counter
      HStack {
        Spacer()
        Text("2/3")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .padding(.top, 60)
          .padding(.trailing, 24)
      }
      .ignoresSafeArea(.container, edges: .top)

      Spacer()

      Image(.alarm)
        .resizable()
        .scaledToFit()
        .frame(width: 100, height: 100)
        .padding(.bottom, 48)
        .opacity(isAnimatingIcon ? 1.0 : 0.0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05), value: isAnimatingIcon)

      VStack(spacing: 16) {
        Text("Alarm")
          .font(.largeTitle.weight(.bold))
          .multilineTextAlignment(.center)
          .opacity(isAnimatingCard ? 1.0 : 0.0)

        Text("Mengingatkanmu supaya tidak\nterlewat stasiun tujuan.")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineSpacing(4)
          .opacity(isAnimatingCard ? 1.0 : 0.0)
      }
      .padding(.horizontal, 32)

      Spacer()
      Spacer()
    }
  }

  // MARK: - Notification Permission Page

  private var notificationPermissionPage: some View {
    VStack(spacing: 0) {
      // Page counter
      HStack {
        Spacer()
        Text("3/3")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .padding(.top, 60)
          .padding(.trailing, 24)
      }
      .ignoresSafeArea(.container, edges: .top)

      Spacer()

      Image(.bell)
        .resizable()
        .scaledToFit()
        .frame(width: 100, height: 100)
        .padding(.bottom, 48)
        .opacity(isAnimatingIcon ? 1.0 : 0.0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05), value: isAnimatingIcon)

      VStack(spacing: 16) {
        Text("Notifikasi")
          .font(.largeTitle.weight(.bold))
          .multilineTextAlignment(.center)
          .opacity(isAnimatingCard ? 1.0 : 0.0)

        Text("Supaya kamu tetap update soal jadwal\ndan info penting lainnya.")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineSpacing(4)
          .opacity(isAnimatingCard ? 1.0 : 0.0)
      }
      .padding(.horizontal, 32)

      Spacer()
      Spacer()
    }
  }

  // MARK: - Final Page

  private var finalPage: some View {
    ZStack {
      celebrationBackground

      VStack(spacing: 0) {
        Spacer()

        // Animated success icon with confetti effect
        ZStack {
          // Confetti particles (more subtle)
          ForEach(0..<8, id: \.self) { index in
            Circle()
              .fill(
                [Color.highlight, Color.yellow, Color.green, Color.blue][
                  index % 4
                ]
              )
              .frame(width: 6, height: 6)
              .offset(
                x: cos(Double(index) * .pi / 4) * (confettiCounter > 0 ? 100 : 0),
                y: sin(Double(index) * .pi / 4) * (confettiCounter > 0 ? 100 : 0)
              )
              .scaleEffect(confettiCounter > 0 ? 0.3 : 1.0)
              .opacity(confettiCounter > 0 ? 0.0 : 1.0)
              .animation(
                .spring(response: 0.7, dampingFraction: 0.7).delay(Double(index) * 0.04),
                value: confettiCounter
              )
          }

          // Background circles
          Circle()
            .fill(Color.highlight.opacity(0.18))
            .frame(width: 220, height: 220)
            .blur(radius: 6)
            .scaleEffect(isAnimatingIcon ? 1.0 : 0.94)
            .opacity(isAnimatingIcon ? 1.0 : 0.0)

          // Main circle with party gradient
          Circle()
            .fill(
              AngularGradient(
                colors: [
                  Color.highlight,
                  Color.yellow.opacity(0.55),
                  Color.green.opacity(0.35),
                  Color.highlight,
                ],
                center: .center
              )
            )
            .frame(width: 170, height: 170)
            .scaleEffect(isAnimatingIcon ? 1.0 : 0.9)
            .opacity(isAnimatingIcon ? 0.4 : 0.0)

          // Inner circle
          Circle()
            .fill(
              LinearGradient(
                colors: [
                  Color.backgroundSecondary.opacity(0.95),
                  Color.backgroundPrimary.opacity(0.65),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(width: 145, height: 145)
            .overlay(
              Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1.5)
                .blur(radius: 0.5)
            )
            .scaleEffect(isAnimatingIcon ? 1.0 : 0.9)
            .opacity(isAnimatingIcon ? 1.0 : 0.0)

          // Party popper icon
          ZStack {
            Image(systemName: "party.popper.fill")
              .font(.system(size: 60))
              .foregroundStyle(.highlight)
              .symbolRenderingMode(.hierarchical)

            // Sparkles (more subtle)
            ForEach(0..<3, id: \.self) { index in
              Image(systemName: "sparkle")
                .font(.system(size: 16))
                .foregroundStyle(.yellow)
                .offset(
                  x: [25, -25, 0][index],
                  y: [-25, 0, 25][index]
                )
                .scaleEffect(isAnimatingIcon ? 1.0 : 0.0)
                .opacity(isAnimatingIcon ? 0.8 : 0.0)
                .animation(
                  .spring(response: 0.5, dampingFraction: 0.7).delay(0.2 + Double(index) * 0.08),
                  value: isAnimatingIcon
                )
            }
          }
          .scaleEffect(isAnimatingIcon ? 1.0 : 0.9)
          .opacity(isAnimatingIcon ? 1.0 : 0.0)
        }
        .padding(.bottom, 48)

        VStack(spacing: 16) {
          Text("Selamat Menikmati!")
            .font(.largeTitle.weight(.bold))
            .multilineTextAlignment(.center)
            .opacity(isAnimatingCard ? 1.0 : 0.0)

          Text(
            "Semua sudah siap!\nSekarang kamu bisa lacak kereta dengan mudah"
          )
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineSpacing(4)
          .opacity(isAnimatingCard ? 1.0 : 0.0)
        }
        .padding(.horizontal, 32)

        Spacer()
        Spacer()
      }
    }
  }

  // MARK: - Controls Overlay

  private var controlsOverlay: some View {
    VStack(spacing: 20) {
      // Page indicators (hide on welcome and final page)
      if shouldShowIndicators {
        HStack(spacing: 8) {
          ForEach(1..<totalPages - 1, id: \.self) { index in
            Capsule()
              .fill(currentPage == index ? Color.highlight : Color.highlight.opacity(0.3))
              .frame(width: currentPage == index ? 28 : 8, height: 8)
              .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentPage)
          }
        }
        .padding(.bottom, 4)
      }

      // Animated action button with skip option
      VStack(spacing: 12) {
        ZStack {
          if currentPage < totalPages - 1 {
            continueButton
              .matchedGeometryEffect(id: ctaId, in: ctaNamespace)
              .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
          }

          if currentPage == totalPages - 1 {
            completionButton
              .background(celebrationCTAGlow)
              .matchedGeometryEffect(id: ctaId, in: ctaNamespace)
              .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
          }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: currentPage)

        if shouldShowSkipButton {
          Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()

            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
              currentPage = totalPages - 1
            }
          } label: {
            Text("Ingatkan Nanti")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          .transition(.opacity)
        }
      }
    }
  }

  // MARK: - Celebration Styling

  private var celebrationBackground: some View {
    ZStack {
      Color.backgroundPrimary
        .opacity(0.98)

      RadialGradient(
        colors: [
          Color.highlight.opacity(0.55),
          Color.highlight.opacity(0.05),
          Color.backgroundPrimary.opacity(0.02),
        ],
        center: .center,
        startRadius: 40,
        endRadius: 480
      )
      .blur(radius: 14)
      .blendMode(.screen)

      AngularGradient(
        colors: [
          Color.highlight.opacity(0.45),
          Color.green.opacity(0.2),
          Color.blue.opacity(0.22),
          Color.highlight.opacity(0.45),
        ],
        center: .center
      )
      .blur(radius: 160)
      .opacity(0.7)

      LinearGradient(
        colors: [
          Color.black.opacity(0.2),
          Color.black.opacity(0.0),
          Color.black.opacity(0.3),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
    .ignoresSafeArea()
  }

  private var celebrationCTAGlow: some View {
    Capsule()
      .fill(
        RadialGradient(
          colors: [
            Color.highlight.opacity(0.85),
            Color.highlight.opacity(0.0),
          ],
          center: .center,
          startRadius: 12,
          endRadius: 160
        )
      )
      .padding(.horizontal, -14)
      .padding(.vertical, -6)
      .blur(radius: 18)
      .opacity(0.8)
  }

  private var continueButton: some View {
    Group {
      if currentPage >= 1 && currentPage <= 3 {
        AnimatedButton(
          title: "Lanjutkan",
          icon: "arrow.right",
          color: .highlight,
          isHighlighted: true,
          isLoading: isRequestingPermission
        ) {
          Task {
            await handlePermissionPageContinue()
          }
        }
      } else {
        AnimatedButton(
          title: "Lanjutkan",
          icon: "arrow.right",
          color: .highlight,
          isHighlighted: true
        ) {
          let impact = UIImpactFeedbackGenerator(style: .medium)
          impact.impactOccurred()

          withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            currentPage += 1
          }
        }
      }
    }
  }

  private var completionButton: some View {
    AnimatedButton(
      title: "Mulai Sekarang",
      icon: "checkmark.circle.fill",
      color: .highlight,
      isHighlighted: true
    ) {
      let impact = UIImpactFeedbackGenerator(style: .heavy)
      impact.impactOccurred()

      handleContinue()
    }
  }

  // Computed property to check if currently requesting any permission
  private var isRequestingPermission: Bool {
    isRequestingLocation || isRequestingAlarm || isRequestingNotification
  }

  private var shouldShowIndicators: Bool {
    currentPage > 0 && currentPage < totalPages - 1
  }

  private var shouldShowSkipButton: Bool {
    currentPage >= 1 && currentPage <= 3
  }

  // MARK: - Actions

  private func refreshPermissionStatuses() async {
    notificationStatus = await permissionService.getNotificationStatus()
    alarmStatus = permissionService.getAlarmStatus()
    locationStatus = permissionService.getLocationStatus()
  }

  private func handlePermissionPageContinue() async {
    // Haptic feedback
    let impact = UIImpactFeedbackGenerator(style: .medium)
    impact.impactOccurred()

    // Request permission based on current page
    switch currentPage {
    case 1:
      // Location permission page
      await requestLocationPermission()
    case 2:
      // Alarm permission page
      await requestAlarmPermission()
    case 3:
      // Notification permission page
      await requestNotificationPermission()
    default:
      break
    }

    // Move to next page after permission request
    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
      currentPage += 1
    }
  }

  private func requestLocationPermission() async {
    isRequestingLocation = true
    defer { isRequestingLocation = false }

    _ = await permissionService.requestLocationPermission()
    await refreshPermissionStatuses()
  }

  private func requestAlarmPermission() async {
    isRequestingAlarm = true
    defer { isRequestingAlarm = false }

    _ = await permissionService.requestAlarmPermission()
    await refreshPermissionStatuses()
  }

  private func requestNotificationPermission() async {
    isRequestingNotification = true
    defer { isRequestingNotification = false }

    _ = await permissionService.requestNotificationPermission()
    await refreshPermissionStatuses()
  }

  private func handleContinue() {
    OnboardingState.markOnboardingComplete()
    dismiss()
  }
}

// MARK: - Animated Button Component

private struct AnimatedButton: View {
  let title: String
  let icon: String
  let color: Color
  let isHighlighted: Bool
  var isLoading: Bool = false
  let action: () -> Void

  @State private var isPressed = false

  var body: some View {
    Button {
      guard !isLoading else { return }

      // Scale animation on press
      withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        isPressed = true
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
          isPressed = false
        }
      }
      action()
    } label: {
      HStack(spacing: 10) {
        if isLoading {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .lessDark))
            .scaleEffect(0.9)
        } else {
          Text(title)
            .font(.headline)

          Image(systemName: icon)
            .font(.headline.weight(.semibold))
        }
      }
      .foregroundStyle(.lessDark)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 18)
      .background(
        ZStack {
          // Base capsule
          Capsule()
            .fill(color.opacity(isHighlighted ? 1.0 : 0.6))

          // Shine effect
          if isHighlighted {
            Capsule()
              .fill(
                LinearGradient(
                  colors: [
                    Color.white.opacity(0.25),
                    Color.white.opacity(0.0),
                    Color.white.opacity(0.08),
                  ],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
          }
        }
        .shadow(
          color: color.opacity(isHighlighted ? 0.3 : 0.15), radius: isPressed ? 6 : 10,
          y: isPressed ? 2 : 3)
      )
      .scaleEffect(isPressed ? 0.98 : 1.0)
      .opacity(isLoading ? 0.8 : 1.0)
    }
    .disabled(isLoading)
    .buttonStyle(.plain)
  }
}

// MARK: - Preview

#Preview {
  PermissionsOnboardingScreen()
}
