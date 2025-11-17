import SwiftUI

@MainActor
@ViewBuilder
func view(for destination: FullScreenDestination) -> some View {
  Group {
    switch destination {
    case .arrival(let stationCode, let stationName):
      TrainArriveScreen(stationCode: stationCode, stationName: stationName)
    case .permissionsOnboarding:
      PermissionsOnboardingScreen()
    }
  }
}

@MainActor
@ViewBuilder
func view(for destination: SheetDestination) -> some View {
  Group {
    switch destination {
    case .feedback:
      FeedbackBoardScreen()
    case .addTrain:
      AddTrainView()
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(true)
    case .shareJourney:
      ShareScreen()
    case .alarmConfiguration:
      AlarmConfigurationSheetContainer()
    }
  }
}

// MARK: - Alarm Configuration Wrapper

private struct AlarmConfigurationSheetContainer: View {
  @Environment(TrainMapStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(Router.self) private var router
  @State private var latestValidationResult: AlarmValidationResult = .valid()

  var body: some View {
    if let train = store.pendingTrainForAlarmConfiguration ?? store.selectedTrain,
      let journeyData = store.pendingJourneyDataForAlarmConfiguration ?? store.selectedJourneyData
    {
      AlarmConfigurationSheet(
        defaultOffset: AlarmPreferences.shared.defaultAlarmOffsetMinutes,
        onValidate: { offset in
          let result = store.validateAlarmTiming(
            offsetMinutes: offset,
            departureTime: journeyData.userSelectedDepartureTime,
            arrivalTime: journeyData.userSelectedArrivalTime
          )
          latestValidationResult = result
          return result
        },
        onContinue: { selectedOffset in
          Task {
            await handleAlarmConfigured(
              offset: selectedOffset,
              train: train,
              journeyData: journeyData
            )
          }
        }
      )
    } else {
      ContentUnavailableView(
        "No Train Selected",
        systemImage: "train.side.front.car",
        description: Text("Please select a train first")
      )
    }
  }

  private func handleAlarmConfigured(
    offset: Int,
    train: ProjectedTrain,
    journeyData: TrainJourneyData
  ) async {
    // Apply alarm configuration (saves preferences and tracks analytics)
    await store.applyAlarmConfiguration(
      offsetMinutes: offset,
      validationResult: latestValidationResult
    )

    // Check if we're updating an existing journey or starting a new one
    let isUpdatingExistingJourney =
      store.pendingTrainForAlarmConfiguration == nil && store.selectedTrain != nil

    if isUpdatingExistingJourney {
      // Just update the alarm configuration for the existing journey
      // refreshAlarmConfiguration is already called by applyAlarmConfiguration
      // No need to restart the live activity or reschedule server alerts
      dismiss()
    } else {
      // Starting a new journey - select the train with alarm offset
      do {
        try await store.selectTrain(
          train,
          journeyData: journeyData,
          alarmOffsetMinutes: offset
        )

        // Clear pending data
        store.pendingTrainForAlarmConfiguration = nil
        store.pendingJourneyDataForAlarmConfiguration = nil

        // Dismiss both the alarm configuration sheet and the parent add train view
        // The dismiss() will handle the alarm configuration sheet
        // We need to dismiss the parent router's sheet (AddTrainView)
        router.parent?.presentingSheet = nil
        dismiss()
      } catch {
        // Handle error - could show an alert here
        print("Failed to select train: \(error)")
      }
    }
  }
}
