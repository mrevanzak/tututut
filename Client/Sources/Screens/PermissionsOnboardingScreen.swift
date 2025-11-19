import AlarmKit
import CoreLocation
import SwiftUI
import UserNotifications

/// Onboarding screen with clean, minimal design
struct PermissionsOnboardingScreen: View {
  @Environment(\.dismiss) private var dismiss

  // State
  @State private var currentPage = 0
  @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
  @State private var alarmStatus: AlarmManager.AuthorizationState = .notDetermined
  @State private var locationStatus: CLAuthorizationStatus = .notDetermined

  @State private var isRequestingNotification = false
  @State private var isRequestingAlarm = false
  @State private var isRequestingLocation = false

  private let permissionService = PermissionRequestService.shared
  private let totalPages = 5

  var body: some View {
    VStack(spacing: 0) {
      // Top Bar (Page Counter)
      HStack {
        Spacer()
        if currentPage > 0 && currentPage < totalPages - 1 {
          Text("\(currentPage)/3")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .transition(.opacity)
        }
      }
      .padding(.horizontal, 24)
      .padding(.top, 16)
      .frame(height: 44)

      // Main Content Area
      TabView(selection: $currentPage) {
        welcomePage.tag(0)
        locationPermissionPage.tag(1)
        alarmPermissionPage.tag(2)
        notificationPermissionPage.tag(3)
        finalPage.tag(4)
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentPage)

      // Bottom Controls
      VStack(spacing: 16) {
        // Primary Button
        Button {
          handleAction()
        } label: {
          HStack {
            if isRequestingPermission {
              ProgressView()
                .tint(.white)
            } else {
              Text(buttonTitle)
                .font(.headline)
                .fontWeight(.bold)
            }
          }
          .frame(maxWidth: .infinity)
          .frame(height: 56)
          .background(Color.highlight)
          .foregroundStyle(.white)
          .clipShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isRequestingPermission)

        // Secondary Button (Skip)
        if shouldShowSkipButton {
          Button {
            withAnimation {
              currentPage = totalPages - 1
            }
          } label: {
            Text("Ingatkan Nanti")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          .buttonStyle(ScaleButtonStyle())
          .transition(.opacity)
        } else {
          // Invisible placeholder to maintain layout height
          Text(" ")
            .font(.subheadline)
            .hidden()
        }
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 16)
      .padding(.top, 24)
    }
    .background(Color.backgroundPrimary)
    .task {
      await refreshPermissionStatuses()
    }
  }

  // MARK: - Pages

  private var welcomePage: some View {
    CleanContentPage(
      icon: .image(.logo),
      title: "Sebelum memulai...",
      description: "Kreta membutuhkan beberapa izin akses.\nKamu bisa mengaturnya lagi melalui Settings."
    )
  }

  private var locationPermissionPage: some View {
    CleanContentPage(
      icon: .image(.location),
      title: "Akses Lokasi",
      description: "Agar kami bisa memandu berdasarkan\nlokasi kamu.",
      status: locationStatus == .authorizedAlways || locationStatus == .authorizedWhenInUse ? .authorized : .none
    )
  }

  private var alarmPermissionPage: some View {
    CleanContentPage(
      icon: .image(.alarm),
      title: "Alarm",
      description: "Mengingatkanmu supaya tidak\ntertinggal kereta atau salah stasiun.",
      status: alarmStatus == .authorized ? .authorized : .none
    )
  }

  private var notificationPermissionPage: some View {
    CleanContentPage(
      icon: .image(.bell),
      title: "Notifikasi",
      description: "Supaya kamu tetap update soal jadwal\ndan info penting lainnya.",
      status: notificationStatus == .authorized ? .authorized : .none
    )
  }

  private var finalPage: some View {
    CleanContentPage(
      icon: .system("checkmark.circle.fill"),
      title: "Semua Siap!",
      description: "Sekarang kamu bisa lacak kereta dengan mudah.\nSelamat menikmati perjalananmu!",
      isFinal: true
    )
  }

  // MARK: - Helpers

  private var buttonTitle: String {
    if currentPage == totalPages - 1 {
      return "Mulai Sekarang"
    }
    
    switch currentPage {
    case 1: return locationStatus == .authorizedAlways || locationStatus == .authorizedWhenInUse ? "Lanjutkan" : "Izinkan Lokasi"
    case 2: return alarmStatus == .authorized ? "Lanjutkan" : "Izinkan Alarm"
    case 3: return notificationStatus == .authorized ? "Lanjutkan" : "Izinkan Notifikasi"
    default: return "Lanjutkan"
    }
  }

  private var shouldShowSkipButton: Bool {
    currentPage > 0 && currentPage < totalPages - 1
  }

  private var isRequestingPermission: Bool {
    isRequestingLocation || isRequestingAlarm || isRequestingNotification
  }

  // MARK: - Actions

  private func handleAction() {
    let impact = UIImpactFeedbackGenerator(style: .medium)
    impact.impactOccurred()

    if currentPage == totalPages - 1 {
      completeOnboarding()
      return
    }

    Task {
      switch currentPage {
      case 1:
        if locationStatus == .notDetermined {
          await requestLocationPermission()
        } else {
          nextPage()
        }
      case 2:
        if alarmStatus == .notDetermined {
          await requestAlarmPermission()
        } else {
          nextPage()
        }
      case 3:
        if notificationStatus == .notDetermined {
          await requestNotificationPermission()
        } else {
          nextPage()
        }
      default:
        nextPage()
      }
    }
  }

  private func nextPage() {
    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
      currentPage += 1
    }
  }

  private func completeOnboarding() {
    OnboardingState.markOnboardingComplete()
    dismiss()
  }

  private func refreshPermissionStatuses() async {
    notificationStatus = await permissionService.getNotificationStatus()
    alarmStatus = permissionService.getAlarmStatus()
    locationStatus = permissionService.getLocationStatus()
  }

  private func requestLocationPermission() async {
    isRequestingLocation = true
    defer { isRequestingLocation = false }
    _ = await permissionService.requestLocationPermission()
    await refreshPermissionStatuses()
    nextPage()
  }

  private func requestAlarmPermission() async {
    isRequestingAlarm = true
    defer { isRequestingAlarm = false }
    _ = await permissionService.requestAlarmPermission()
    await refreshPermissionStatuses()
    nextPage()
  }

  private func requestNotificationPermission() async {
    isRequestingNotification = true
    defer { isRequestingNotification = false }
    _ = await permissionService.requestNotificationPermission()
    await refreshPermissionStatuses()
    nextPage()
  }
}

// MARK: - Subviews

private enum IconSource {
  case image(ImageResource)
  case system(String)
}

private struct CleanContentPage: View {
  let icon: IconSource
  let title: String
  let description: String
  var status: PermissionsOnboardingScreen.OnboardingContent.PermissionStatus = .none
  var isFinal: Bool = false
  
  @State private var appear = false
  
  var body: some View {
    VStack(spacing: 0) {
      Spacer()
      
      // Icon
      Group {
        switch icon {
        case .image(let resource):
          Image(resource)
            .resizable()
            .scaledToFit()
            .frame(width: 120, height: 120)
        case .system(let name):
          Image(systemName: name)
            .font(.system(size: 80))
            .foregroundStyle(isFinal ? Color.highlight : Color.primary)
            .frame(width: 120, height: 120)
        }
      }
      .scaleEffect(appear ? 1.0 : 0.5)
      .opacity(appear ? 1.0 : 0.0)
      .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: appear)
      .padding(.bottom, 32)
      
      // Text Content
      VStack(spacing: 12) {
        Text(title)
          .font(.title2)
          .bold()
          .multilineTextAlignment(.center)
          .foregroundStyle(.primary)
          .opacity(appear ? 1.0 : 0.0)
          .offset(y: appear ? 0 : 10)
          .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: appear)
        
        Text(description)
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineSpacing(4)
          .opacity(appear ? 1.0 : 0.0)
          .offset(y: appear ? 0 : 10)
          .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: appear)
      }
      .padding(.horizontal, 32)
      
      // Status Indicator
      if status == .authorized {
        HStack(spacing: 6) {
          Image(systemName: "checkmark.circle.fill")
          Text("Diizinkan")
            .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.green)
        .padding(.top, 24)
        .transition(.scale.combined(with: .opacity))
      }
      
      Spacer()
      Spacer() // Push content up slightly visually
    }
    .onAppear {
      appear = true
    }
  }
}

struct ScaleButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
      .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
  }
}

// Extension to support the nested type reference
extension PermissionsOnboardingScreen {
  struct OnboardingContent {
    enum PermissionStatus {
      case none, authorized, notDetermined
    }
  }
}

#Preview {
  PermissionsOnboardingScreen()
}
