//
//  AddTrainViewModel.swift
//  kreta
//
//  Created by Gilang Banyu Biru Erassunu on 23/10/25.
//

import Foundation
import Observation
import SwiftUI

// MARK: - Selection Step

enum SelectionStep {
  case departure
  case arrival
  case date
  case results
}

// MARK: - Journey Data

struct TrainJourneyData: Codable, Equatable {
  let trainId: String
  let segments: [JourneySegment]
  let allStations: [Station]

  let userSelectedFromStation: Station
  let userSelectedToStation: Station
  let userSelectedDepartureTime: Date
  let userSelectedArrivalTime: Date
  let selectedDate: Date  // The date user selected for the journey
}

// MARK: - Logiks
extension TrainJourneyData {
  func stopStationIds(dwellThreshold seconds: TimeInterval = 30) -> [String] {
    guard !segments.isEmpty else { return [] }

    var stops: [String] = []
    stops.append(segments[0].fromStationId)

    if segments.count >= 2 {
      for i in 0..<(segments.count - 1) {
        let prevSeg = segments[i]
        let nextSeg = segments[i + 1]

        // Sanity: these should meet at the same station
        let intermediateStation = prevSeg.toStationId
        if intermediateStation == nextSeg.fromStationId {
          // Server already normalized times, use directly
          let dwell = nextSeg.departure.timeIntervalSince(prevSeg.arrival)
          if dwell >= seconds { stops.append(intermediateStation) }
        } else {
          // If segments don't meet (data glitch), be conservative: don't add as stop.
          // You can log here if you want.
        }
      }
    }

    stops.append(segments.last!.toStationId)

    var seen = Set<String>()
    let ordered = stops.filter { seen.insert($0).inserted }
    return ordered
  }
}

// MARK: - AddTrainView Extension

extension AddTrainView {
  @MainActor
  @Observable
  final class ViewModel {
    // MARK: - Properties

    var allStations: [Station] = []
    var connectedStations: [Station] = []
    var availableTrains: [JourneyService.AvailableTrainItem] = []
    var filteredTrains: [JourneyService.AvailableTrainItem] = []

    // Store journey data separately from ProjectedTrain
    var trainJourneyData: [String: TrainJourneyData] = [:]

    var currentStep: SelectionStep = .departure
    var searchText: String = ""
    var selectedTrainNameFilter: String = "Semua Kereta"  // Picker selection for train filtering
    var showCalendar: Bool = false
    var isLoadingConnections: Bool = false
    var isLoadingTrains: Bool = false

    var selectedDepartureStation: Station?
    var selectedArrivalStation: Station?
    var selectedDate: Date?

    // Selected train item (for confirmation before tracking)
    var selectedTrainItem: JourneyService.AvailableTrainItem?

    // MARK: - Private Properties

    private let stationConnectionService = StationConnectionService()
    private let trainConnectionService = TrainConnectionService()
    private let journeyService = JourneyService()
    private let trainStopService = TrainStopService()

    // no longer caching all journeys; server provides list DTOs

    // MARK: - Public Methods

    func bootstrap(allStations: [Station]) {
      self.allStations = allStations
      AnalyticsEventService.shared.trackTrainSearchInitiated()
    }

    /// Fetch connected stations for the selected departure station
    func fetchConnectedStations() async {
      guard let departureId = selectedDepartureStation?.id else {
        connectedStations = []
        return
      }

      isLoadingConnections = true
      defer { isLoadingConnections = false }

      do {
        connectedStations = try await stationConnectionService.fetchConnectedStations(
          departureStationId: departureId
        )
      } catch {
        print(
          "Failed to fetch connected stations for departureId: \(departureId), error: \(error.localizedDescription)"
        )
        connectedStations = []
      }
    }

    /// Fetch trains that connect the selected departure and arrival stations
    func fetchAvailableTrains() async {
      guard let departureId = selectedDepartureStation?.id,
        let arrivalId = selectedArrivalStation?.id
      else {
        filteredTrains = []
        return
      }

      isLoadingTrains = true
      defer { isLoadingTrains = false }

      do {
        // Use new TrainStopService for efficient server-side filtering
        // This query only returns trains that actually stop at both stations
        let trainRoutes = try await trainStopService.findTrainsByRoute(
          departureStationId: departureId,
          arrivalStationId: arrivalId
        )

        // Convert TrainRouteJourney to AvailableTrainItem
        // Note: We still need to call the existing API to get the full journey data with routes
        var items: [JourneyService.AvailableTrainItem] = []

        for _ in trainRoutes {
          // Fetch full journey data for trains that actually stop at both stations
          let targetDate = selectedDate ?? Date()
          let fullItems = try await journeyService.fetchProjectedForRoute(
            departureStationId: departureId,
            arrivalStationId: arrivalId,
            selectedDate: targetDate
          )

          // Filter to only include the trains from trainStopService
          let validTrainIds = Set(trainRoutes.map { $0.trainId })
          items = fullItems.filter { validTrainIds.contains($0.trainId) }
          break  // Only need to fetch once
        }

        filteredTrains = items
      } catch {
        print(
          "Failed to fetch available trains for route: departureId=\(departureId), arrivalId=\(arrivalId), error: \(error.localizedDescription)"
        )
        filteredTrains = []
      }
    }
    /// Toggle selection of a train item
    func toggleTrainSelection(_ item: JourneyService.AvailableTrainItem) {
      if selectedTrainItem?.id == item.id {
        selectedTrainItem = nil
      } else {
        selectedTrainItem = item
      }
    }

    /// Check if a train item is currently selected
    func isTrainSelected(_ item: JourneyService.AvailableTrainItem) -> Bool {
      selectedTrainItem?.id == item.id
    }

    /// Build and select a ProjectedTrain from a selected list item
    func didSelect(_ item: JourneyService.AvailableTrainItem) async -> ProjectedTrain {
      let stationsById = StationLookupHelper.buildStationsById(allStations)
      guard
        let fromStation = stationsById[item.fromStationId]
          ?? StationLookupHelper.findStation(
            by: item.fromStationId,
            in: allStations
          ),
        let toStation = stationsById[item.toStationId]
          ?? StationLookupHelper.findStation(
            by: item.toStationId,
            in: allStations
          )
      else {
        print(
          "Failed to find stations for train item: fromStationId=\(item.fromStationId), toStationId=\(item.toStationId)"
        )
        // Return a minimal ProjectedTrain as fallback
        return ProjectedTrain(
          id: item.id,
          code: item.code,
          name: item.name,
          position: Position(latitude: 0, longitude: 0),
          moving: false,
          bearing: nil,
          routeIdentifier: item.routeId,
          speedKph: nil,
          fromStation: nil,
          toStation: nil,
          segmentDeparture: item.segmentDeparture,
          segmentArrival: item.segmentArrival,
          progress: nil,
          journeyDeparture: item.segmentDeparture,
          journeyArrival: item.segmentArrival
        )
      }

      // Server already normalized times to selected date
      let targetDate = selectedDate ?? Date()
      let userDeparture = item.segmentDeparture
      let userArrival = item.segmentArrival

      do {
        let segments = try await journeyService.fetchSegmentsForTrain(
          trainId: item.trainId,
          selectedDate: targetDate
        )

        // Build journey segments and collect stations using JourneyDataBuilder
        let (journeySegments, allStationsInJourney) = JourneyDataBuilder.buildSegmentsAndStations(
          from: segments,
          stationsById: stationsById
        )

        // Store journey data separately
        trainJourneyData[item.trainId] = JourneyDataBuilder.buildTrainJourneyData(
          trainId: item.trainId,
          segments: journeySegments,
          allStations: allStationsInJourney,
          fromStation: fromStation,
          toStation: toStation,
          userSelectedDepartureTime: userDeparture,
          userSelectedArrivalTime: userArrival,
          selectedDate: targetDate
        )
      } catch {
        print(
          "Failed to fetch journey segments for trainId: \(item.trainId), error: \(error.localizedDescription)"
        )
        // Continue with available data - we still have the basic train info
      }

      // Track selected train
      AnalyticsEventService.shared.trackTrainSelected(item: item)

      // Create ProjectedTrain with server-normalized times
      let projected = ProjectedTrain(
        id: item.id,
        code: item.code,
        name: item.name,
        position: Position(
          latitude: fromStation.position.latitude,
          longitude: fromStation.position.longitude
        ),
        moving: false,
        bearing: nil,
        routeIdentifier: item.routeId,
        speedKph: nil,
        fromStation: fromStation,
        toStation: toStation,
        segmentDeparture: userDeparture,
        segmentArrival: userArrival,
        progress: nil,
        journeyDeparture: userDeparture,
        journeyArrival: userArrival
      )

      return projected
    }

    func parseAndSelectDate(from text: String) {
      if let date = parseDateFromText(text) {
        selectDate(date)
      }
    }

    func selectStation(_ station: Station) {
      switch currentStep {
      case .departure:
        selectedDepartureStation = station
        AnalyticsEventService.shared.trackStationSelected(
          station: station, selectionType: "departure")
        currentStep = .arrival
        searchText = ""
        // Fetch connected stations in background
        Task {
          await fetchConnectedStations()
        }
      case .arrival:
        selectedArrivalStation = station
        AnalyticsEventService.shared.trackStationSelected(
          station: station, selectionType: "arrival")
        currentStep = .date
        searchText = ""
      default:
        break
      }
    }

    func selectDate(_ date: Date) {
      selectedDate = date
      showCalendar = false
      currentStep = .results
      // Fetch trains for the selected route
      Task {
        await fetchAvailableTrains()
      }
    }

    func showCalendarView() {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        showCalendar = true
      }
    }

    func hideCalendar() {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        selectedDate = nil
        showCalendar = false
      }
    }

    func goBackToDeparture() {
      selectedDepartureStation = nil
      selectedArrivalStation = nil
      selectedDate = nil
      connectedStations = []
      filteredTrains = []
      selectedTrainNameFilter = "Semua Kereta"
      showCalendar = false
      currentStep = .departure
      searchText = ""
    }

    func goBackToArrival() {
      selectedArrivalStation = nil
      selectedDate = nil
      filteredTrains = []
      selectedTrainNameFilter = "Semua Kereta"
      showCalendar = false
      currentStep = .arrival
      searchText = ""
      // Re-fetch connected stations
      Task {
        await fetchConnectedStations()
      }
    }

    func goBackToDate() {
      selectedDate = nil
      filteredTrains = []
      selectedTrainNameFilter = "Semua Kereta"
      showCalendar = false
      currentStep = .date
      searchText = ""
    }

    func reset() {
      currentStep = .departure
      selectedDepartureStation = nil
      selectedArrivalStation = nil
      selectedDate = nil
      searchText = ""
      selectedTrainNameFilter = "Semua Kereta"
      connectedStations = []
      filteredTrains = []
      showCalendar = false
    }

    // MARK: - Computed Properties

    var filteredStations: [Station] {
      let stations: [Station]

      switch currentStep {
      case .departure:
        stations = allStations
      case .arrival:
        stations = connectedStations
      case .date, .results:
        return []
      }

      if searchText.isEmpty {
        return stations.sorted { $0.name < $1.name }
      }

      let filtered = stations.filter { station in
        station.name.localizedCaseInsensitiveContains(searchText)
          || station.code.localizedCaseInsensitiveContains(searchText)
          || (station.city?.localizedCaseInsensitiveContains(searchText) ?? false)
      }

      // Sort with exact name matches first, then alphabetically
      return filtered.sorted { lhs, rhs in
        let lhsNameMatch = lhs.name.localizedCaseInsensitiveCompare(searchText) == .orderedSame
        let rhsNameMatch = rhs.name.localizedCaseInsensitiveCompare(searchText) == .orderedSame

        // Exact name matches come first
        if lhsNameMatch && !rhsNameMatch {
          return true
        } else if !lhsNameMatch && rhsNameMatch {
          return false
        }

        // Both are exact matches or both are not - sort alphabetically
        return lhs.name < rhs.name
      }
    }

    var uniqueTrainNames: [String] {
      let names = Set(filteredTrains.map { $0.name }).sorted()
      return ["Semua Kereta"] + names
    }

    var searchableTrains: [JourneyService.AvailableTrainItem] {
      let trains: [JourneyService.AvailableTrainItem]

      if selectedTrainNameFilter == "Semua Kereta" {
        trains = filteredTrains
      } else {
        trains = filteredTrains.filter { item in
          item.name == selectedTrainNameFilter
        }
      }

      // Sort by train name alphabetically, then by departure time
      return trains.sorted { lhs, rhs in
        // First compare by train name
        let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameComparison != .orderedSame {
          return nameComparison == .orderedAscending
        }

        // If same train name, sort by departure time (earliest first)
        return lhs.segmentDeparture < rhs.segmentDeparture
      }
    }

    var stepTitle: String {
      if showCalendar {
        return "Pilih Tanggal"
      }

      switch currentStep {
      case .departure:
        return "Pilih Stasiun Keberangkatan"
      case .arrival:
        return "Pilih Stasiun Tujuan"
      case .date:
        return "Keberangkatan Tujuan"
      case .results:
        return "Keberangkatan Tujuan"
      }
    }

    // MARK: - Private Methods

    private func parseDateFromText(_ text: String) -> Date? {
      let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

      // Handle common Indonesian date patterns
      // e.g., "24 oktober", "24/10", "24-10", "24 okt"
      let calendar = Calendar.current
      let currentYear = calendar.component(.year, from: Date())

      // Pattern: "DD Month" or "DD MMM"
      let monthNames = [
        "januari": 1, "februari": 2, "maret": 3, "april": 4,
        "mei": 5, "juni": 6, "juli": 7, "agustus": 8,
        "september": 9, "oktober": 10, "november": 11, "desember": 12,
        "jan": 1, "feb": 2, "mar": 3, "apr": 4,
        "jun": 6, "jul": 7, "agu": 8, "ags": 8,
        "sep": 9, "okt": 10, "nov": 11, "des": 12,
      ]

      // Try to parse "DD Month" format
      let components = cleanText.components(separatedBy: .whitespaces)
      if components.count >= 2,
        let day = Int(components[0]),
        let month = monthNames[components[1]]
      {
        var dateComponents = DateComponents()
        dateComponents.year = currentYear
        dateComponents.month = month
        dateComponents.day = day
        return calendar.date(from: dateComponents)
      }

      // Try DD/MM or DD-MM format
      let separators = CharacterSet(charactersIn: "/-")
      let parts = cleanText.components(separatedBy: separators)
      if parts.count >= 2,
        let day = Int(parts[0]),
        let month = Int(parts[1])
      {
        var dateComponents = DateComponents()
        dateComponents.year = currentYear
        dateComponents.month = month
        dateComponents.day = day
        return calendar.date(from: dateComponents)
      }

      return nil
    }

  }
}
