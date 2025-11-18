import Foundation

// MARK: - CompletedJourney

struct CompletedJourney: Codable, Identifiable, Sendable {
  let id: String  // CloudKit record ID
  let trainId: String
  let trainCode: String
  let trainName: String

  // Station information
  let fromStationId: String
  let fromStationCode: String
  let fromStationName: String
  let toStationId: String
  let toStationCode: String
  let toStationName: String

  // Timing information
  let selectedDate: Date
  let userSelectedDepartureTime: Date
  let userSelectedArrivalTime: Date
  let actualArrivalTime: Date
  let journeyDurationMinutes: Int

  // Journey segments summary
  let segmentCount: Int
  let routeIds: [String?]  // Array of route IDs from segments

  // Completion metadata
  let completionType: String  // "arrival_screen" | "scheduled_arrival"
  let wasTrackedUntilArrival: Bool

  // MARK: - Custom Coding Keys for CloudKit

  private enum CodingKeys: String, CodingKey {
    case id
    case trainId
    case trainCode
    case trainName
    case fromStationId
    case fromStationCode
    case fromStationName
    case toStationId
    case toStationCode
    case toStationName
    case selectedDate
    case userSelectedDepartureTime
    case userSelectedArrivalTime
    case actualArrivalTime
    case journeyDurationMinutes
    case segmentCount
    case routeIds
    case completionType
    case wasTrackedUntilArrival
  }

  // MARK: - Initializers

  init(
    id: String = UUID().uuidString,
    trainId: String,
    trainCode: String,
    trainName: String,
    fromStationId: String,
    fromStationCode: String,
    fromStationName: String,
    toStationId: String,
    toStationCode: String,
    toStationName: String,
    selectedDate: Date,
    userSelectedDepartureTime: Date,
    userSelectedArrivalTime: Date,
    actualArrivalTime: Date,
    journeyDurationMinutes: Int,
    segmentCount: Int,
    routeIds: [String?],
    completionType: String,
    wasTrackedUntilArrival: Bool,
  ) {
    self.id = id
    self.trainId = trainId
    self.trainCode = trainCode
    self.trainName = trainName
    self.fromStationId = fromStationId
    self.fromStationCode = fromStationCode
    self.fromStationName = fromStationName
    self.toStationId = toStationId
    self.toStationCode = toStationCode
    self.toStationName = toStationName
    self.selectedDate = selectedDate
    self.userSelectedDepartureTime = userSelectedDepartureTime
    self.userSelectedArrivalTime = userSelectedArrivalTime
    self.actualArrivalTime = actualArrivalTime
    self.journeyDurationMinutes = journeyDurationMinutes
    self.segmentCount = segmentCount
    self.routeIds = routeIds
    self.completionType = completionType
    self.wasTrackedUntilArrival = wasTrackedUntilArrival
  }
}
