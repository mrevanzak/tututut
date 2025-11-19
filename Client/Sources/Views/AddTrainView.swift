//
//  AddTrainView.swift
//  kreta
//
//  Created by Gilang Banyu Biru Erassunu on 22/10/25.
//

import OSLog
import SwiftUI

struct AddTrainView: View {
  @Environment(Router.self) private var router
  @Environment(TrainMapStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.showToast) private var showToast

  @State private var viewModel: ViewModel = ViewModel()
  @State private var isSearchBarOverContent: Bool = false
  @State private var isPresentingAlarmConfiguration: Bool = false

  private let logger = Logger(subsystem: "kreta", category: "AddTrainView")

  // MARK: - Body

  var body: some View {
    VStack(spacing: 0) {
      headerView()
      contentView()
    }
    .padding(.top)
    .task {
      viewModel.bootstrap(allStations: store.stations)
    }
    .background(.backgroundPrimary)
    .sheet(isPresented: $isPresentingAlarmConfiguration) {
      AlarmConfigurationSheetContainer()
    }
  }

  // MARK: - Header View

  private func headerView() -> some View {
    VStack(alignment: .leading, spacing: 8) {
      headerTitleSection
      searchBarSection
    }
    .padding()
  }

  private var headerTitleSection: some View {
    HStack {
      VStack(alignment: .leading) {
        Text("Tambah Perjalanan Kereta")
          .font(.title2.weight(.bold))

        StepTitleView(
          text: viewModel.stepTitle,
          showCalendar: viewModel.showCalendar
        )
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

  private var searchBarSection: some View {
    AnimatedSearchBar(
      step: viewModel.currentStep,
      departureStation: viewModel.selectedDepartureStation,
      arrivalStation: viewModel.selectedArrivalStation,
      selectedDate: viewModel.selectedDate,
      searchText: $viewModel.searchText,
      onDepartureChipTap: {
        viewModel.goBackToDeparture()
      },
      onArrivalChipTap: {
        viewModel.goBackToArrival()
      },
      onDateChipTap: {
        viewModel.goBackToDate()
      },
      onDateTextSubmit: {
        viewModel.parseAndSelectDate(from: viewModel.searchText)
      }
    )
  }

  // MARK: - Content View

  @ViewBuilder
  private func contentView() -> some View {
    switch viewModel.currentStep {
    case .departure, .arrival:
      stationListView()
    case .date:
      dateSelectionView()
    case .results:
      trainResultsView()
    }
  }

  // MARK: - Station List View

  private func stationListView() -> some View {
    List(viewModel.filteredStations) { station in
      StationRow(station: station)
        .onTapGesture {
          viewModel.selectStation(station)
        }
        .listRowBackground(Color.clear)
    }
    .listStyle(.plain)
    .overlay {
      stationListOverlay
    }
  }

  @ViewBuilder
  private var stationListOverlay: some View {
    if viewModel.isLoadingConnections {
      ProgressView()
        .controlSize(.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.backgroundPrimary)
    } else if viewModel.filteredStations.isEmpty {
      ContentUnavailableView.search(text: viewModel.searchText)
    }
  }

  // MARK: - Date Selection View

  @ViewBuilder
  private func dateSelectionView() -> some View {
    ZStack {
      if viewModel.showCalendar {
        calendarView()
          .transition(.move(edge: .trailing))
      } else {
        datePickerView()
          .transition(.move(edge: .leading))
      }
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.showCalendar)
  }

  private func datePickerView() -> some View {
    VStack(spacing: 16) {
      todayOption
      Divider()
      tomorrowOption
      Divider()
      customDateOption
      Spacer()
    }
    .padding()
  }

  private var todayOption: some View {
    DateOptionRow(
      icon: "calendar.badge.clock",
      title: "Hari ini",
      subtitle: Date().formatted(.dateTime.weekday(.wide).day().month(.wide))
    )
    .onTapGesture {
      viewModel.selectDate(Date())
    }
  }

  private var tomorrowOption: some View {
    DateOptionRow(
      icon: "calendar",
      title: "Besok",
      subtitle: tomorrowDateString
    )
    .onTapGesture {
      if let tomorrow = tomorrowDate {
        viewModel.selectDate(tomorrow)
      }
    }
  }

  private var customDateOption: some View {
    DateOptionRow(
      icon: "calendar.badge.plus",
      title: "Pilih berdasarkan hari",
      subtitle: ""
    )
    .onTapGesture {
      viewModel.showCalendarView()
    }
  }

  private var tomorrowDate: Date? {
    Calendar.current.date(byAdding: .day, value: 1, to: Date())
  }

  private var tomorrowDateString: String {
    (tomorrowDate ?? Date()).formatted(.dateTime.weekday(.wide).day().month(.wide))
  }

  private func calendarView() -> some View {
    CalendarView(
      selectedDate: Binding(
        get: { viewModel.selectedDate ?? Date() },
        set: { viewModel.selectedDate = $0 }
      ),
      onDateSelected: { date in
        viewModel.selectDate(date)
      },
      onBack: {
        viewModel.hideCalendar()
      }
    )
  }

  // MARK: - Train Results View

  private func trainResultsView() -> some View {
    TrainResultsView(
      trains: viewModel.searchableTrains,
      uniqueTrainNames: viewModel.uniqueTrainNames,
      selectedTrainNameFilter: viewModel.selectedTrainNameFilter,
      isLoading: viewModel.isLoadingTrains,
      isTrainSelected: { viewModel.isTrainSelected($0) },
      onTrainTapped: { viewModel.toggleTrainSelection($0) },
      onTrainSelected: {
        handleTrainSelectionAction()
      },
      onFilterChanged: { viewModel.selectedTrainNameFilter = $0 },
      selectedTrainItem: viewModel.selectedTrainItem,
      isSearchBarOverContent: $isSearchBarOverContent
    )
  }

  // MARK: - Train Selection Handlers

  private func handleTrainSelectionAction() {
    guard let selectedItem = viewModel.selectedTrainItem else { return }
    Task {
      let projected = await viewModel.didSelect(selectedItem)
      logger.info(
        "handleTrainSelectionAction resolved projected train \(projected.id, privacy: .public)")
      await handleTrainSelection(projected)
    }
  }

  private func handleTrainSelection(_ train: ProjectedTrain) async {
    guard let journeyData = viewModel.trainJourneyData[train.id] else {
      logger.error("No journeyData found for train \(train.id, privacy: .public)")
      return
    }

    if !AlarmPreferences.shared.hasCompletedInitialSetup {
      logger.info("Alarm setup incomplete. Storing pending train \(train.id, privacy: .public)")
      // Store pending data in store for alarm configuration sheet
      store.pendingTrainForAlarmConfiguration = train
      store.pendingJourneyDataForAlarmConfiguration = journeyData
      logger.info("Navigating to alarm configuration sheet")
      isPresentingAlarmConfiguration = true
    } else {
      logger.info(
        "Alarm setup complete. Proceeding without sheet for train \(train.id, privacy: .public)")
      await proceedWithTrainSelection(
        train: train,
        journeyData: journeyData,
        alarmOffsetMinutes: nil
      )
    }
  }

  private func proceedWithTrainSelection(
    train: ProjectedTrain,
    journeyData: TrainJourneyData,
    alarmOffsetMinutes: Int?
  ) async {
    do {
      try await store.selectTrain(
        train,
        journeyData: journeyData,
        alarmOffsetMinutes: alarmOffsetMinutes
      )
      logger.info("Successfully selected train \(train.id, privacy: .public)")
      dismiss()
    } catch {
      logger.error(
        "Failed to select train \(train.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      showToast("Failed to select train: \(error)")
    }
  }
}

// MARK: - Preview

#Preview("Add Train View") {
  let store = TrainMapStore.preview

  store.stations = [
    Station(
      id: "GMR",
      code: "GMR",
      name: "Gambir",
      position: Position(latitude: -6.1774, longitude: 106.8306),
      city: "Jakarta"
    ),
    Station(
      id: "JNG",
      code: "JNG",
      name: "Jatinegara",
      position: Position(latitude: -6.2149, longitude: 106.8707),
      city: "Jakarta"
    ),
    Station(
      id: "BD",
      code: "BD",
      name: "Bandung",
      position: Position(latitude: -6.9175, longitude: 107.6191),
      city: "Bandung"
    ),
    Station(
      id: "YK",
      code: "YK",
      name: "Yogyakarta",
      position: Position(latitude: -7.7956, longitude: 110.3695),
      city: "Yogyakarta"
    ),
    Station(
      id: "SB",
      code: "SB",
      name: "Surabaya Gubeng",
      position: Position(latitude: -7.2655, longitude: 112.7523),
      city: "Surabaya"
    ),
  ]

  return AddTrainView()
    .environment(store)
}
