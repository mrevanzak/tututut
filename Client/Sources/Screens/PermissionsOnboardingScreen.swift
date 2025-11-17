import AlarmKit
import CoreLocation
import SwiftUI
import UserNotifications

/// Onboarding screen for requesting app permissions
struct PermissionsOnboardingScreen: View {
  @Environment(\.dismiss) private var dismiss

  @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
  @State private var alarmStatus: AlarmManager.AuthorizationState = .notDetermined
  @State private var locationStatus: CLAuthorizationStatus = .notDetermined

  @State private var isRequestingNotification = false
  @State private var isRequestingAlarm = false
  @State private var isRequestingLocation = false

  private let permissionService = PermissionRequestService.shared

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 32) {
          // Header
          headerView

          // Permission sections
          VStack(spacing: 24) {
            notificationPermissionSection
            alarmPermissionSection
            locationPermissionSection
          }

        }
        .padding()
      }
      .background(Color.backgroundPrimary)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Lewati") {
            handleContinue()
          }
        }
      }
      .task {
        await refreshPermissionStatuses()
      }
    }
    .safeAreaInset(edge: .bottom) {
      continueButton
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Color.backgroundPrimary.opacity(0.98))
        .shadow(color: Color.black.opacity(0.05), radius: 12, y: -2)
    }
  }

  // MARK: - Header

  private var headerView: some View {
    VStack(spacing: 12) {
      Image(systemName: "lock.shield.fill")
        .font(.system(size: 48))
        .foregroundStyle(.highlight)
        .symbolRenderingMode(.hierarchical)

      Text("Izinkan Akses")
        .font(.title2.weight(.bold))

      Text(
        "Kreta membutuhkan beberapa izin untuk memberikan pengalaman terbaik. Kamu bisa mengatur ini nanti di Pengaturan."
      )
      .font(.body)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .padding(.horizontal)
    }
    .padding(.top)
  }

  // MARK: - Notification Permission Section

  private var notificationPermissionSection: some View {
    PermissionSection(
      icon: "bell.fill",
      title: "Notifikasi",
      description:
        "Dapatkan pemberitahuan tentang perjalanan kereta, kedatangan stasiun, dan pembaruan penting lainnya.",
      status: notificationStatusText,
      statusColor: notificationStatusColor,
      buttonText: notificationButtonText,
      isRequesting: isRequestingNotification,
      isEnabled: notificationStatus == .notDetermined,
      action: {
        Task {
          await requestNotificationPermission()
        }
      }
    )
  }

  private var notificationStatusText: String {
    switch notificationStatus {
    case .notDetermined:
      return "Belum diizinkan"
    case .authorized, .provisional, .ephemeral:
      return "Diizinkan"
    case .denied:
      return "Ditolak"
    @unknown default:
      return "Tidak diketahui"
    }
  }

  private var notificationStatusColor: Color {
    switch notificationStatus {
    case .notDetermined:
      return .orange
    case .authorized, .provisional, .ephemeral:
      return .green
    case .denied:
      return .red
    @unknown default:
      return .gray
    }
  }

  private var notificationButtonText: String {
    switch notificationStatus {
    case .notDetermined:
      return "Izinkan Notifikasi"
    case .authorized, .provisional, .ephemeral:
      return "Sudah Diizinkan"
    case .denied:
      return "Buka Pengaturan"
    @unknown default:
      return "Izinkan Notifikasi"
    }
  }

  // MARK: - Alarm Permission Section

  private var alarmPermissionSection: some View {
    PermissionSection(
      icon: "alarm.fill",
      title: "Alarm",
      description:
        "Dapatkan alarm penting sebelum tiba di stasiun tujuan agar kamu tidak melewatkan pemberhentian.",
      status: alarmStatusText,
      statusColor: alarmStatusColor,
      buttonText: alarmButtonText,
      isRequesting: isRequestingAlarm,
      isEnabled: alarmStatus == .notDetermined,
      action: {
        Task {
          await requestAlarmPermission()
        }
      }
    )
  }

  private var alarmStatusText: String {
    switch alarmStatus {
    case .notDetermined:
      return "Belum diizinkan"
    case .authorized:
      return "Diizinkan"
    case .denied:
      return "Ditolak"
    @unknown default:
      return "Tidak diketahui"
    }
  }

  private var alarmStatusColor: Color {
    switch alarmStatus {
    case .notDetermined:
      return .orange
    case .authorized:
      return .green
    case .denied:
      return .red
    @unknown default:
      return .gray
    }
  }

  private var alarmButtonText: String {
    switch alarmStatus {
    case .notDetermined:
      return "Izinkan Alarm"
    case .authorized:
      return "Sudah Diizinkan"
    case .denied:
      return "Buka Pengaturan"
    @unknown default:
      return "Izinkan Alarm"
    }
  }

  // MARK: - Location Permission Section

  private var locationPermissionSection: some View {
    PermissionSection(
      icon: "location.fill",
      title: "Lokasi",
      description:
        "Deteksi ketika kamu mendekati stasiun untuk memberikan pemberitahuan yang tepat waktu.",
      status: locationStatusText,
      statusColor: locationStatusColor,
      buttonText: locationButtonText,
      isRequesting: isRequestingLocation,
      isEnabled: locationStatus == .notDetermined,
      action: {
        Task {
          await requestLocationPermission()
        }
      }
    )
  }

  private var locationStatusText: String {
    switch locationStatus {
    case .notDetermined:
      return "Belum diizinkan"
    case .authorizedWhenInUse, .authorizedAlways:
      return "Diizinkan"
    case .denied, .restricted:
      return "Ditolak"
    @unknown default:
      return "Tidak diketahui"
    }
  }

  private var locationStatusColor: Color {
    switch locationStatus {
    case .notDetermined:
      return .orange
    case .authorizedWhenInUse, .authorizedAlways:
      return .green
    case .denied, .restricted:
      return .red
    @unknown default:
      return .gray
    }
  }

  private var locationButtonText: String {
    switch locationStatus {
    case .notDetermined:
      return "Izinkan Lokasi"
    case .authorizedWhenInUse, .authorizedAlways:
      return "Sudah Diizinkan"
    case .denied, .restricted:
      return "Buka Pengaturan"
    @unknown default:
      return "Izinkan Lokasi"
    }
  }

  // MARK: - Continue Button

  private var continueButton: some View {
    let isEnabled = hasAllPermissions

    return Button {
      handleContinue()
    } label: {
      Text("Lanjutkan")
        .font(.headline)
        .foregroundStyle(isEnabled ? .lessDark : .lessDark.opacity(0.6))
        .frame(maxWidth: .infinity)
        .padding()
        .background(
          Capsule()
            .fill(.highlight.opacity(isEnabled ? 1.0 : 0.35))
        )
    }
    .disabled(!isEnabled)
  }

  // MARK: - Actions

  private func refreshPermissionStatuses() async {
    notificationStatus = await permissionService.getNotificationStatus()
    alarmStatus = permissionService.getAlarmStatus()
    locationStatus = permissionService.getLocationStatus()
  }

  private func requestNotificationPermission() async {
    isRequestingNotification = true
    defer { isRequestingNotification = false }

    let granted = await permissionService.requestNotificationPermission()
    await refreshPermissionStatuses()

    if !granted && notificationStatus == .denied {
      // Could open settings here if needed
    }
  }

  private func requestAlarmPermission() async {
    isRequestingAlarm = true
    defer { isRequestingAlarm = false }

    let granted = await permissionService.requestAlarmPermission()
    await refreshPermissionStatuses()

    if !granted && alarmStatus == .denied {
      // Could open settings here if needed
    }
  }

  private func requestLocationPermission() async {
    isRequestingLocation = true
    defer { isRequestingLocation = false }

    let granted = await permissionService.requestLocationPermission()
    await refreshPermissionStatuses()

    if !granted && (locationStatus == .denied || locationStatus == .restricted) {
      // Could open settings here if needed
    }
  }

  private func handleContinue() {
    OnboardingState.markOnboardingComplete()
    dismiss()
  }

  // MARK: - Permission Helpers

  private var hasAllPermissions: Bool {
    isNotificationGranted && isAlarmGranted && isLocationGranted
  }

  private var isNotificationGranted: Bool {
    switch notificationStatus {
    case .authorized, .provisional, .ephemeral:
      return true
    default:
      return false
    }
  }

  private var isAlarmGranted: Bool {
    alarmStatus == .authorized
  }

  private var isLocationGranted: Bool {
    switch locationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      return true
    default:
      return false
    }
  }
}

// MARK: - Permission Section Component

private struct PermissionSection: View {
  let icon: String
  let title: String
  let description: String
  let status: String
  let statusColor: Color
  let buttonText: String
  let isRequesting: Bool
  let isEnabled: Bool
  let action: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.title2)
          .foregroundStyle(.highlight)
          .frame(width: 32)

        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.headline)

          Text(description)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()
      }

      HStack {
        HStack(spacing: 6) {
          Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)

          Text(status)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Button {
          action()
        } label: {
          if isRequesting {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .white))
              .frame(width: 20, height: 20)
          } else {
            Text(buttonText)
              .font(.subheadline.weight(.medium))
          }
        }
        .buttonStyle(.borderedProminent)
        .tint(.highlight)
        .disabled(!isEnabled && !isRequesting)
      }
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.systemBackground))
        .shadow(color: Color(.systemGray).opacity(0.1), radius: 8, x: 0, y: 4)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color(.separator), lineWidth: 1)
    )
  }
}

// MARK: - Preview

#Preview {
  PermissionsOnboardingScreen()
}
