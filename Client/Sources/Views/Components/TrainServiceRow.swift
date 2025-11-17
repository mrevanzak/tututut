//
//  TrainServiceRow.swift
//  tututut
//
//  Created by Gilang Banyu Biru Erassunu on 24/10/25.
//

import SwiftUI

struct TrainServiceRow: View {
  let item: JourneyService.AvailableTrainItem
  var isSelected: Bool = false

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      // Train service details
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 4) {
          Text(item.name)
            .font(.title3).bold()
          Text("(\(item.code))")
            .font(.subheadline)
            .foregroundStyle(.textSecondary)
        }

        // Route information
        HStack(spacing: 8) {
          // Departure station
          HStack(spacing: 4) {
            Text(item.fromStationCode ?? "--")
              .font(.subheadline)
              .foregroundStyle(.textSecondary)

            Text(
              formatTime(item.segmentDeparture)
            )
            .font(.subheadline).bold()
          }

          // Direction arrow
          Image(systemName: "arrow.right.square.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.backgroundPrimary, .highlight)
            .font(.subheadline)

          // Arrival station
          HStack(spacing: 4) {
            Text(item.toStationCode ?? "--")
              .font(.subheadline)
              .foregroundStyle(.textSecondary)

            Text(
              formatTime(item.segmentArrival)
            )
            .font(.subheadline).bold()
          }
        }
      }

      Spacer()
    }
    .background(isSelected ? .backgroundSecondary : Color.clear)
  }

  private func formatTime(_ date: Date?) -> String {
    guard let date else { return "--:--" }
    return date.formatted(.dateTime.hour().minute())
  }
}

#Preview {
  let stations = [
    Station(
      code: "GMR",
      name: "Gambir",
      position: Position(latitude: -6.1774, longitude: 106.8306),
      city: nil
    ),
    Station(
      code: "JNG",
      name: "Jatinegara",
      position: Position(latitude: -6.2149, longitude: 106.8707),
      city: nil
    ),
  ]

  // Create test item by decoding from JSON since AvailableTrainItem has custom Decodable
  let testJSON: [String: Any] = [
    "id": "T1",
    "trainId": "T1",
    "code": "T1",
    "name": "Sample Express",
    "fromStationId": "GMR",
    "toStationId": "JNG",
    "segmentDeparture": Int64(Date().addingTimeInterval(-15 * 60).timeIntervalSince1970 * 1000),
    "segmentArrival": Int64(Date().addingTimeInterval(15 * 60).timeIntervalSince1970 * 1000),
    "routeId": "L1",
    "fromStationName": stations[0].name,
    "toStationName": stations[1].name,
    "fromStationCode": stations[0].code,
    "toStationCode": stations[1].code,
    "durationMinutes": 30,
  ]

  let item = try! JSONDecoder().decode(
    JourneyService.AvailableTrainItem.self,
    from: JSONSerialization.data(withJSONObject: testJSON)
  )

  return VStack(spacing: 0) {
    TrainServiceRow(item: item, isSelected: false)
    Divider()
    TrainServiceRow(item: item, isSelected: true)
  }
}
