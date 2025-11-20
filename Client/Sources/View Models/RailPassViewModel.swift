import Combine
import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class RailPassViewModel {
  var stats: RailPassStats = RailPassStats()
  var journeys: [CompletedJourney] = []
  var isLoading: Bool = false
  var errorMessage: String?

  private let historyService = JourneyHistoryService.shared

  func loadData(stations: [Station]) async {
    isLoading = true
    errorMessage = nil

    do {
      // Fetch all history (or a reasonable limit for now)
      let fetchedJourneys = try await historyService.fetchJourneyHistory(limit: 1000)
      self.journeys = fetchedJourneys
      calculateStats(journeys: fetchedJourneys, stations: stations)
    } catch {
      errorMessage = "Gagal memuat riwayat perjalanan: \(error.localizedDescription)"
    }

    isLoading = false
  }

  private func calculateStats(journeys: [CompletedJourney], stations: [Station]) {
    var totalDist: Double = 0
    var totalDur: Int = 0
    var uniqueStations = Set<String>()
    var uniqueTrains = Set<String>()

    // Create a lookup for stations by ID and Code for faster access
    let stationLookup = Dictionary(uniqueKeysWithValues: stations.map { ($0.code, $0) })
    // Fallback lookup by ID if needed, though code is primary in CompletedJourney for now

    for journey in journeys {
      totalDur += journey.journeyDurationMinutes
      uniqueTrains.insert(journey.trainCode)

      // Add stations to unique set
      uniqueStations.insert(journey.fromStationCode)
      uniqueStations.insert(journey.toStationCode)

      // Calculate distance
      if let fromStation = stationLookup[journey.fromStationCode],
        let toStation = stationLookup[journey.toStationCode]
      {
        let fromLoc = CLLocation(
          latitude: fromStation.position.latitude, longitude: fromStation.position.longitude)
        let toLoc = CLLocation(
          latitude: toStation.position.latitude, longitude: toStation.position.longitude)
        let dist = fromLoc.distance(from: toLoc)  // in meters
        totalDist += dist
      }
    }

    self.stats = RailPassStats(
      totalJourneys: journeys.count,
      totalDistanceKm: totalDist / 1000.0,
      totalDurationMinutes: totalDur,
      uniqueStationsCount: uniqueStations.count,
      uniqueTrainsCount: uniqueTrains.count
    )
  }
}
