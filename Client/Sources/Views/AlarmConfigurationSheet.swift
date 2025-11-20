import SwiftUI

// MARK: - Alarm Validation Result

struct AlarmValidationResult {
  let isValid: Bool
  let reason: AlarmValidationFailureReason?

  enum AlarmValidationFailureReason {
    case arrivalInPast(minutesUntilArrival: Int)
    case insufficientTimeForAlarm(minutesUntilArrival: Int, requestedOffset: Int)
    case alarmBeforeDeparture(journeyDuration: Int, requestedOffset: Int)
    case journeyTooShort(journeyDuration: Int, requestedOffset: Int, minimumRequired: Int)
  }

  static func valid() -> AlarmValidationResult {
    AlarmValidationResult(isValid: true, reason: nil)
  }

  static func invalid(_ reason: AlarmValidationFailureReason) -> AlarmValidationResult {
    AlarmValidationResult(isValid: false, reason: reason)
  }
}

// MARK: - Alarm Configuration Sheet

struct AlarmConfigurationSheet: View {
  @Environment(\.dismiss) private var dismiss

  @State private var selectedOffset: Int
  @State private var showValidationAlert = false
  @State private var validationResult: AlarmValidationResult?

  let onContinue: (Int) -> Void
  let onValidate: ((Int) -> AlarmValidationResult)?
  let defaultOffset: Int

  // MARK: - Initialization

  init(
    defaultOffset: Int = 10,
    onValidate: ((Int) -> AlarmValidationResult)? = nil,
    onContinue: @escaping (Int) -> Void
  ) {
    self.defaultOffset = defaultOffset
    self._selectedOffset = State(initialValue: defaultOffset)
    self.onValidate = onValidate
    self.onContinue = onContinue
  }

  // MARK: - Body

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        // New header title section
        headerTitleSection

        // Original header view remains below
        headerView

        // Picker
        pickerView

        Spacer()

        // Continue Button
        continueButton
      }
      .padding()
      .background(Color.backgroundPrimary)
      .alert("Pengaturan Alarm Tidak Optimal", isPresented: $showValidationAlert) {
        alertButtons
      } message: {
        alertMessage
      }
      .onAppear {
        // Pre-validate default offset when sheet appears
        // If invalid, suggest a valid offset
        if let validate = onValidate {
          let result = validate(selectedOffset)
          if !result.isValid {
            // Try to find a valid offset
            if let validOffset = findValidOffset(
              startingFrom: selectedOffset,
              validate: validate
            ) {
              selectedOffset = validOffset
            }
          }
        }
      }
    }
  }

  // MARK: - Helper Methods

  /// Find a valid offset starting from the given offset, trying smaller values first
  private func findValidOffset(
    startingFrom offset: Int,
    validate: (Int) -> AlarmValidationResult
  ) -> Int? {
    // Try smaller offsets first (more likely to be valid)
    for testOffset in stride(from: offset, through: 1, by: -1) {
      if validate(testOffset).isValid {
        return testOffset
      }
    }
    // If no smaller valid offset found, try larger ones
    for testOffset in (offset + 1)...60 {
      if validate(testOffset).isValid {
        return testOffset
      }
    }
    return nil
  }

  // MARK: - Subviews

  private var headerTitleSection: some View {
    HStack {
      VStack(alignment: .leading) {
        Text("Atur Pengingat Kedatangan")
          .font(.title2.weight(.bold))

        Text("Atur alarm sesuai dengan preferensi anda")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Spacer()

      closeButton
    }
  }

  private var closeButton: some View {
    Button {
      dismiss()
    } label: {
      Image(systemName: "xmark.circle.fill")
        .symbolRenderingMode(.palette)
        .foregroundStyle(.textSecondary, .primary)
        .font(.largeTitle)
    }
    .foregroundStyle(.backgroundSecondary)
    .glassEffect(.regular.tint(.backgroundSecondary))
  }

  private var headerView: some View {
    VStack(spacing: 12) {
      Image("Alarm")
        .font(.system(size: 48))
        .foregroundStyle(.highlight)
        .symbolRenderingMode(.hierarchical)

      Text(
        "Kamu akan menerima alarm sebelum tiba di tujuan. Pilih berapa menit sebelum kedatangan:"
      )
      .font(.body)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
    }
    .padding(.top)
  }

  private var pickerView: some View {
    VStack(spacing: 8) {
      Text("Waktu Alarm")
        .font(.caption)
        .foregroundStyle(.secondary)

      Picker("Offset Alarm", selection: $selectedOffset) {
        ForEach(1...60, id: \.self) { minutes in
          Text("\(minutes) menit")
            .tag(minutes)
        }
      }
      .pickerStyle(.wheel)
      .frame(height: 150)
      .clipped()
    }
  }

  private var continueButton: some View {
    Button {
      handleContinue()
    } label: {
      Text("Lanjutkan")
        .font(.headline)
        .foregroundStyle(.lessDark)
        .frame(maxWidth: .infinity)
        .padding()
        .background(.highlight)
        .cornerRadius(1000)
    }
  }

  // MARK: - Alert Components

  @ViewBuilder
  private var alertButtons: some View {
    Button("Ubah Pengaturan", role: .cancel) {
      showValidationAlert = false
    }

    Button("Lanjutkan") {
      showValidationAlert = false
      proceedWithConfiguration()
    }
  }

  @ViewBuilder
  private var alertMessage: some View {
    if let reason = validationResult?.reason {
      switch reason {
      case .arrivalInPast:
        Text(
          "Kereta sudah tiba atau sedang tiba sekarang. Alarm tidak dapat diatur untuk perjalanan yang sudah selesai. Lanjutkan tanpa alarm?"
        )

      case .insufficientTimeForAlarm(let minutesUntilArrival, let requestedOffset):
        Text(
          "Kereta tiba dalam \(minutesUntilArrival) menit, alarm \(requestedOffset) menit tidak akan berbunyi. Ubah pengaturan alarm atau lanjutkan tanpa alarm?"
        )

      case .alarmBeforeDeparture(let journeyDuration, let requestedOffset):
        Text(
          "Alarm \(requestedOffset) menit akan berbunyi sebelum kereta berangkat (perjalanan hanya \(journeyDuration) menit). Pilih alarm yang lebih kecil atau lanjutkan tanpa alarm?"
        )

      case .journeyTooShort(let journeyDuration, let requestedOffset, let minimumRequired):
        Text(
          "Perjalanan hanya \(journeyDuration) menit, alarm \(requestedOffset) menit memerlukan perjalanan minimal \(minimumRequired) menit. Ubah pengaturan atau lanjutkan?"
        )
      }
    }
  }

  // MARK: - Actions

  private func handleContinue() {
    // Validate if validator provided
    if let validate = onValidate {
      let result = validate(selectedOffset)
      validationResult = result

      if !result.isValid {
        showValidationAlert = true
        return
      }
    }

    proceedWithConfiguration()
  }

  private func proceedWithConfiguration() {
    onContinue(selectedOffset)
    dismiss()
  }
}

// MARK: - Preview

#Preview("Configuration Sheet") {
  AlarmConfigurationSheet(
    defaultOffset: 10,
    onValidate: { offset in
      // Mock validation
      if offset > 30 {
        return .invalid(
          .journeyTooShort(journeyDuration: 25, requestedOffset: offset, minimumRequired: 40))
      }
      if offset > 20 {
        return .invalid(
          .alarmBeforeDeparture(journeyDuration: 25, requestedOffset: offset))
      }
      return .valid()
    },
    onContinue: { offset in
      print("Selected offset: \(offset)")
    }
  )
}
