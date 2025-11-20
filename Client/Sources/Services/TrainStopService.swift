//
//  TrainStopService.swift
//  kreta
//
//  Created by AI Assistant
//

import ConvexMobile
import Foundation

@MainActor
final class TrainStopService {
  private let convexClient = Dependencies.shared.convexClient

  // MARK: - Models

  struct TrainStop: Codable, Sendable {
    let sequence: Int
    let stationId: String
    let stationCode: String
    let stationName: String
    let city: String
    let arrivalTime: String?
    let departureTime: String?
    let isOrigin: Bool
    let isDestination: Bool

    private enum CodingKeys: String, CodingKey {
      case sequence
      case stationId
      case stationCode
      case stationName
      case city
      case arrivalTime
      case departureTime
      case isOrigin
      case isDestination
    }
  }

  struct TrainSchedule: Codable, Sendable {
    let trainCode: String
    let trainName: String
    let trainId: String
    let route: RouteInfo
    let totalStops: Int
    let stops: [TrainStop]

    struct RouteInfo: Codable, Sendable {
      let origin: String
      let destination: String
    }
  }

  struct TrainRouteJourney: Codable, Sendable {
    let trainId: String
    let trainCode: String
    let trainName: String
    let departureStation: StationInfo
    let departureTime: String?
    let departureSequence: Int
    let arrivalStation: StationInfo
    let arrivalTime: String?
    let arrivalSequence: Int
    let stopsBetween: Int

    struct StationInfo: Codable, Sendable {
      let id: String
      let code: String
      let name: String
      let city: String
    }
  }

  struct RouteDetails: Codable, Sendable {
    let trainCode: String
    let trainName: String
    let trainId: String
    let journey: JourneyInfo
    let stops: [StopInfo]

    struct JourneyInfo: Codable, Sendable {
      let from: String
      let to: String
      let departureTime: String?
      let arrivalTime: String?
      let totalStops: Int
    }

    struct StopInfo: Codable, Sendable {
      let sequence: Int
      let stationName: String
      let city: String
      let arrivalTime: String?
      let departureTime: String?
    }
  }

  struct TrainSummary: Codable, Sendable {
    let trainId: String
    let trainCode: String
    let trainName: String
    let origin: String
    let destination: String
    let totalStops: Int
  }

  struct TrainAtStation: Codable, Sendable, Identifiable {
    let trainId: String
    let trainCode: String
    let trainName: String
    let stationId: String
    let stationCode: String
    let stationName: String
    let city: String
    let arrivalTime: String?
    let departureTime: String?
    let stopSequence: Int
    let origin: String
    let destination: String
    let isOrigin: Bool
    let isDestination: Bool

    var id: String { trainId }

    var displayTime: String {
      if let departure = departureTime {
        return departure
      } else if let arrival = arrivalTime {
        return arrival
      }
      return "--:--:--"
    }
  }

  struct ConnectedStation: Codable, Sendable, Identifiable {
    let stationId: String
    let stationCode: String
    let stationName: String
    let city: String
    let trainIds: [String]
    let trainCount: Int

    var id: String { stationId }
  }

  // MARK: - Public Methods

  /// Get complete train schedule with all stops
  func getTrainSchedule(trainCode: String) async throws -> TrainSchedule? {
    return try await convexClient.query(
      to: "trainStops:getTrainSchedule",
      with: ["trainCode": trainCode],
      yielding: TrainSchedule?.self
    )
  }

  /// Find all trains that actually stop at both departure and arrival stations
  /// This replaces the heavy client-side filtering with efficient server-side query
  func findTrainsByRoute(
    departureStationId: String,
    arrivalStationId: String
  ) async throws -> [TrainRouteJourney] {
    return try await convexClient.query(
      to: "trainStops:findTrainsByRoute",
      with: [
        "departureStationId": departureStationId,
        "arrivalStationId": arrivalStationId,
      ],
      yielding: [TrainRouteJourney].self
    )
  }

  /// Get detailed route information with intermediate stops
  func getRouteDetails(
    trainCode: String,
    departureStationId: String,
    arrivalStationId: String
  ) async throws -> RouteDetails? {
    return try await convexClient.query(
      to: "trainStops:getRouteDetails",
      with: [
        "trainCode": trainCode,
        "departureStationId": departureStationId,
        "arrivalStationId": arrivalStationId,
      ],
      yielding: RouteDetails?.self
    )
  }

  /// List all available trains (summary)
  func listAllTrains() async throws -> [TrainSummary] {
    return try await convexClient.query(
      to: "trainStops:listAllTrains",
      with: [:],
      yielding: [TrainSummary].self
    )
  }

  /// Get all trains that stop at a specific station
  func getTrainsAtStation(stationId: String) async throws -> [TrainAtStation] {
    return try await convexClient.query(
      to: "trainStops:getTrainsAtStation",
      with: ["stationId": stationId],
      yielding: [TrainAtStation].self
    )
  }

  /// Get all stations connected to a given station
  /// Returns stations that share at least one train route with the queried station
  func getConnectedStations(stationId: String) async throws -> [ConnectedStation] {
    return try await convexClient.query(
      to: "trainStops:getConnectedStations",
      with: ["stationId": stationId],
      yielding: [ConnectedStation].self
    )
  }
}
