//
//  StationConnectionService.swift
//  kreta
//
//  Created by Gilang Banyu Biru Erassunu on 30/10/25.
//

import Combine
import ConvexMobile
import Foundation

@MainActor
final class StationConnectionService {
  private let convexClient = Dependencies.shared.convexClient

  /// Fetch connected stations for a given departure station
  func fetchConnectedStations(departureStationId: String) async throws -> [Station] {
    let connectedStations = try await convexClient.query(
      to: "trainStops:getConnectedStations",
      with: ["stationId": departureStationId],
      yielding: [TrainStopService.ConnectedStation].self
    )
    
    // Convert ConnectedStation to Station
    return connectedStations.map { connected in
      Station(
        id: connected.stationId,
        code: connected.stationCode,
        name: connected.stationName,
        position: Position(latitude: 0, longitude: 0), // Position not available from this endpoint
        city: connected.city,
      )
    }
  }

}
