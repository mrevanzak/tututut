//
//  StationRow.swift
//  tututut
//
//  Created by Gilang Banyu Biru Erassunu on 24/10/25.
//

import SwiftUI

struct StationRow: View {
  @ScaledMetric(relativeTo: .title3) private var badgeSize: CGFloat = 56
  let station: Station
  var isNearestStation: Bool = false

  var body: some View {
    HStack(spacing: 12) {
      // Station code badge
      ZStack {
        Circle()
          .foregroundStyle(.backgroundSecondary)
          .glassEffect(.regular.tint(.primary))
          .frame(width: 44)

        Text(station.code)
          .font(.callout)
          .foregroundStyle(.primary)

      }

      // Station name
      VStack(alignment: .leading, spacing: 4) {
        Text(station.name)
          .font(.title3)

        Text(station.city ?? "Unknown City")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()
      
      // Nearest station badge
      if isNearestStation {
        HStack(spacing: 4) {
          Image(systemName: "star.fill")
            .font(.subheadline)
            .foregroundStyle(.sublime)
          
          Text("Stasiun Terdekat")
            .font(.subheadline)
            .foregroundStyle(.sublime)
        }
        .padding(.horizontal, 8)
      }

    }
    .contentShape(Rectangle())
  }
}

#Preview {
  let station = Station(
    code: "JNG",
    name: "Jatinegara",
    position: Position(latitude: -6.2149, longitude: 106.8707),
    city: "Jakarta"
  )
  StationRow(station: station)
}
