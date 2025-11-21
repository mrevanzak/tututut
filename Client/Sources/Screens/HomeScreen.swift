import MapKit
import SwiftUI

// MARK: - Main Map Screen

struct HomeScreen: View {
  @Environment(Router.self) private var router
  @Environment(\.colorScheme) private var colorScheme
  @State private var trainMapStore = TrainMapStore()

  @State private var isFollowing: Bool = true
  @State private var focusTrigger: Bool = false
  @State private var selectedDetent: PresentationDetent = .height(240)
  @State private var showingDeleteAlert = false

  private var isPortalActive: Binding<Bool> {
    Binding(
      get: { selectedDetent == .large },
      set: { active in
        selectedDetent = active ? .large : .height(240)
      }
    )
  }

  var gradient: LinearGradient {
    let colors: [Color]

    if colorScheme == .dark {
      // Dark mode gradient
      colors = [
        .black.opacity(0.5),
        .white,
        .black.opacity(0.5),
      ]
    } else {
      // Light mode gradient
      colors = [
        .clear,
        .white,
        .clear,
      ]
    }

    return LinearGradient(
      colors: colors,
      startPoint: UnitPoint(x: 0.0, y: 0.0),
      endPoint: UnitPoint(x: 1.0, y: 1.0)
    )
  }

  var body: some View {
    Group {
      TrainMapView()
        .sheet(isPresented: .constant(true)) {
          // Bottom card or full journey view
          Group {
            if selectedDetent == .large, let train = trainMapStore.selectedTrain,
              let selectedDate = trainMapStore.selectedJourneyData?.selectedDate
            {
              // Full journey progress view
              let displayTrain = trainMapStore.liveTrainPosition ?? train
              JourneyProgressView(
                train: displayTrain,
                journeyData: trainMapStore.selectedJourneyData,
                selectedDate: selectedDate,
                onDelete: {
                  deleteTrain()
                  selectedDetent = .height(240)
                }
              )
            } else if selectedDetent == .height(80), let train = trainMapStore.selectedTrain {
              // Minimal view with train name and destination
              minimalTrainView(train: trainMapStore.liveTrainPosition ?? train)
            } else {
              // Compact view with train name header and train card or add button
              compactBottomSheet
            }
          }
          .presentationBackgroundInteraction(.enabled)
          .presentationDetents(presentationDetents, selection: $selectedDetent)
          .presentationDragIndicator(trainMapStore.selectedTrain == nil ? .hidden : .visible)
          .interactiveDismissDisabled(true)
          .animation(.easeInOut(duration: 0.3), value: trainMapStore.selectedTrain?.id)
          .animation(.easeInOut(duration: 0.3), value: selectedDetent)
          .onChange(of: trainMapStore.selectedTrain) { oldValue, newValue in
            // Reset to compact when train changes or is removed
            if newValue == nil {
              selectedDetent = .fraction(0.35)
            } else if oldValue?.id != newValue?.id {
              selectedDetent = .height(240)
            }
          }
          .routerPresentation(router: router)
          .task {
            // Show permissions onboarding on first launch
            if !OnboardingState.hasCompletedOnboarding() {
              router.navigate(to: .fullScreen(.permissionsOnboarding))
            }
          }
        }
    }
    .environment(trainMapStore)
    .task {
      try? await trainMapStore.loadSelectedTrainFromCache()
    }
  }

  // MARK: - Computed Properties

  private var presentationDetents: Set<PresentationDetent> {
    if trainMapStore.selectedTrain != nil {
      return [.height(80), .height(240), .large]
    } else {
      return [.fraction(0.2)]
    }
  }

  // MARK: - Subviews

  @ViewBuilder
  private func minimalTrainView(train: ProjectedTrain) -> some View {
    let destinationStation =
      trainMapStore.selectedJourneyData?.userSelectedToStation.code
      ?? train.toStation?.code
      ?? "Tujuan"

    VStack(alignment: .leading, spacing: 4) {
      Text("\(train.name) Menuju \(destinationStation)")
        .font(.title2.weight(.bold))
        .foregroundStyle(.primary)

      Text(formatRemainingTime(train: train))
        .font(.subheadline)
        .foregroundStyle(Color(hex: "818181"))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 12)
    .padding(.horizontal)
  }

  @ViewBuilder
  private var compactBottomSheet: some View {
    VStack(alignment: .leading, spacing: 10) {
      // Show train name header if train is selected
      if let train = trainMapStore.selectedTrain {
        HStack(alignment: .center) {
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
              Text(train.name)
                .font(.title2)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.primary)
              Text("(\(train.code))")
                .fontWeight(.bold)
                .foregroundStyle(.sublime)
            }

            if let date = trainMapStore.selectedJourneyData?.selectedDate {
              Text(date.formatted(.dateTime.day().month(.wide).year()))
                .font(.subheadline)
                .foregroundStyle(.blue)
            }
          }

          Spacer()

          Button(action: {
            showingDeleteAlert = true
          }) {
            ZStack {
              Circle()
                .strokeBorder(.gray.opacity(0.2), lineWidth: 1)
                .frame(width: 44, height: 44)

              Circle()
                .strokeBorder(self.gradient, lineWidth: 1)
                .opacity(1 * 1.2)
                .frame(width: 44, height: 44)

              Image(systemName: "trash")
                .foregroundStyle(.red)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())

          }
          .alert("Hapus Tracking Kereta?", isPresented: $showingDeleteAlert) {
            Button("Hapus", role: .destructive) {
              deleteTrain()
            }
            Button("Batal", role: .cancel) {}
          } message: {
            Text("Kreta akan berhenti melacak \(train.name) (\(train.code))")
          }

          HStack(spacing: 12) {
            Menu {
              Button("Atur Alarm Kedatangan", systemImage: "bell.badge") {
                router.navigate(to: .sheet(.alarmConfiguration))
              }

              Button("Feedback Board", systemImage: "bubble.left.and.bubble.right") {
                router.navigate(to: .sheet(.feedback))
              }

              Button("Rail Pass", systemImage: "map.circle") {
                router.navigate(to: .sheet(.railPass))
              }

              #if DEBUG
                Divider()

                Menu("🧪 Proximity Debug", systemImage: "location.circle") {
                  Button("Show Pending Notifications", systemImage: "list.bullet") {
                    Task {
                      await StationProximityService.shared.debugPendingNotifications()
                    }
                  }

                  Button("Force Refresh Triggers", systemImage: "arrow.clockwise") {
                    Task {
                      await StationProximityService.shared.forceRefresh()
                    }
                  }

                  Divider()

                  Button("Test: Malang Station", systemImage: "bell.badge.fill") {
                    Task {
                      await StationProximityService.shared.testProximityNotification(
                        stationCode: "ML")
                    }
                  }

                  Button("Test: Pasar Senen", systemImage: "bell.badge.fill") {
                    Task {
                      await StationProximityService.shared.testProximityNotification(
                        stationCode: "PSE")
                    }
                  }

                  Button("Test: Gambir", systemImage: "bell.badge.fill") {
                    Task {
                      await StationProximityService.shared.testProximityNotification(
                        stationCode: "GMR")
                    }
                  }
                }
              #endif
            } label: {
              ZStack {
                Circle()
                  .strokeBorder(.gray.opacity(0.2), lineWidth: 1)
                  .frame(width: 44, height: 44)

                Circle()
                  .strokeBorder(self.gradient, lineWidth: 1)
                  .opacity(1 * 1.2)
                  .frame(width: 44, height: 44)

                Image(systemName: "ellipsis")
                  .foregroundStyle(.textSecondary)
              }
              .frame(width: 44, height: 44)
              .contentShape(Circle())

            }
          }
        }
        .padding(.top)
      } else {
        // Show "Perjalanan Kereta" only when no train is selected
        HStack(alignment: .center) {
          //          Text("Perjalanan Kereta")
          //            .font(.title2).bold()
          Button {
            router.navigate(to: .sheet(.addTrain))
          } label: {
            HStack(spacing: 10) {
              Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

              Text("Cari Stasiun Keberangkatan")
                .font(.subheadline)
                .foregroundColor(.gray)

              Spacer()
            }
            .frame(height: 44)
            .padding(.horizontal)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
          }
          .buttonStyle(.plain)
          Spacer()

          Menu {
            Button("Feedback Board", systemImage: "bubble.left.and.bubble.right") {
              router.navigate(to: .sheet(.feedback))
            }

            Button("Rail Pass", systemImage: "map.circle") {
              router.navigate(to: .sheet(.railPass))
            }

            #if DEBUG
              Divider()

              Menu("🧪 Proximity Debug", systemImage: "location.circle") {
                Button("Show Pending Notifications", systemImage: "list.bullet") {
                  Task {
                    await StationProximityService.shared.debugPendingNotifications()
                  }
                }

                Button("Force Refresh Triggers", systemImage: "arrow.clockwise") {
                  Task {
                    await StationProximityService.shared.forceRefresh()
                  }
                }

                Divider()

                Button("Test: Malang Station", systemImage: "bell.badge.fill") {
                  Task {
                    await StationProximityService.shared.testProximityNotification(
                      stationCode: "ML")
                  }
                }

                Button("Test: Pasar Senen", systemImage: "bell.badge.fill") {
                  Task {
                    await StationProximityService.shared.testProximityNotification(
                      stationCode: "PSE")
                  }
                }

                Button("Test: Gambir", systemImage: "bell.badge.fill") {
                  Task {
                    await StationProximityService.shared.testProximityNotification(
                      stationCode: "GMR")
                  }
                }
              }
            #endif
          } label: {
            ZStack {
              Circle()
                .strokeBorder(.gray.opacity(0.2), lineWidth: 1)
                .frame(width: 44, height: 44)

              Circle()
                .strokeBorder(self.gradient, lineWidth: 1)
                .opacity(1 * 1.2)
                .frame(width: 44, height: 44)

              Image(systemName: "ellipsis")
                .foregroundStyle(.textSecondary)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
          }
        }
      }

      // Show train if available, otherwise show add button
      if let train = trainMapStore.selectedTrain {
        // Use live projected train if available, otherwise use original
        let displayTrain = trainMapStore.liveTrainPosition ?? train
        TrainCard(
          train: displayTrain,
          journeyData: trainMapStore.selectedJourneyData,
          onDelete: {
            deleteTrain()
          }
        )
        .transition(
          .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
          ))
      } else {
        VStack(alignment: .leading, spacing: 24) {

          // SEARCH FIELD (replaces add train button)
          //              Button {
          //                  router.navigate(to: .sheet(.addTrain))
          //              } label: {
          //                  HStack(spacing: 10) {
          //                      Image(systemName: "magnifyingglass")
          //                          .foregroundColor(.gray)
          //
          //                      Text("Cari Stasiun Keberangkatan")
          //                          .foregroundColor(.gray)
          //
          //                      Spacer()
          //                  }
          //                  .padding()
          //                  //                  .frame(height: 44)
          //                  .background(.ultraThinMaterial)
          //                  .clipShape(RoundedRectangle(cornerRadius: 20))
          //              }
          //              .buttonStyle(.plain)

          // Grey train icon + title + subtitle (UI only)
          HStack(alignment: .center, spacing: 12) {
            Image("LogoMono")
              .resizable()
              .scaledToFit()
              .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
              Text("Yuk, Naik Kereta")
                .font(.title3).bold()
                .foregroundColor(.sublime)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

              Text("Tekan search untuk track perjalananmu")
                .foregroundColor(.sublime)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            }
            .containerRelativeFrame(.horizontal) { size, _ in
              size * 0.5
            }

            AnimatedArrowView()
              .frame(width: 50, height: 48)
              .offset(x: -5, y: -25)
          }
          .padding(.horizontal, 4)
          .padding(.vertical)
        }
        .transition(
          .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
          ))
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  // MARK: - Actions

  private func formatRemainingTime(train: ProjectedTrain) -> String {
    // Use journey data if available for user-selected times
    let departure =
      trainMapStore.selectedJourneyData?.userSelectedDepartureTime ?? train.journeyDeparture
    let arrival = trainMapStore.selectedJourneyData?.userSelectedArrivalTime ?? train.journeyArrival

    guard let departure = departure, let arrival = arrival else {
      return "Waktu tidak tersedia"
    }

    let now = Date()

    // Check if train hasn't departed yet
    if now < departure {
      return "Kereta belum berangkat"
    }

    // Check if train has already arrived
    if now >= arrival {
      return "Sudah Tiba"
    }

    // Calculate time remaining until arrival (mirrors TrainCard logic)
    let timeInterval = arrival.timeIntervalSince(now)
    let totalMinutes = Int(timeInterval / 60)

    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    // Return only the time string without "Tiba Dalam"
    if hours > 0 && minutes > 0 {
      return "\(hours) Jam \(minutes) Menit"
    } else if hours > 0 {
      return "\(hours) Jam"
    } else if minutes > 0 {
      return "\(minutes) Menit"
    } else {
      return "Tiba Sebentar Lagi"
    }
  }

  private func deleteTrain() {
    Task { @MainActor in
      await trainMapStore.clearSelectedTrain()
    }
  }

  @ViewBuilder
  func navigationView(for destination: SheetDestination, from router: Router)
    -> some View
  {
    NavigationContainer(parentRouter: router) { view(for: destination) }
  }

  @ViewBuilder
  func navigationView(for destination: FullScreenDestination, from router: Router)
    -> some View
  {
    NavigationContainer(parentRouter: router) { view(for: destination) }
  }

}
