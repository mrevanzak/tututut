import MapKit
import SwiftUI
import UIKit

struct RailPassShareView: View {
  let stats: RailPassStats
  let routes: [Route]
  let stations: [Station]

  // Fixed size for 9:16 story (e.g. 1080x1920 scaled down)
  // We'll rely on the renderer to scale it, but we design for this aspect ratio

  var body: some View {
    ZStack {
      // Background
      Color(uiColor: UIColor.systemBackground)

      VStack(spacing: 0) {
        // Map Section (Top half)
        Map {
          ForEach(routes) { route in
            MapPolyline(coordinates: route.coordinates)
              .stroke(Color.blue, lineWidth: 3)
          }

          ForEach(stations) { station in
            Annotation(station.code, coordinate: station.coordinate) {
              Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.blue, lineWidth: 2))
            }
          }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: 500)  // Adjust based on need
        .disabled(true)

        // Stats Section (Bottom half)
        VStack(alignment: .leading, spacing: 24) {

          VStack(alignment: .leading, spacing: 4) {
            Text("RAIL PASS")
              .font(.caption)
              .fontWeight(.bold)
              .tracking(2)
              .foregroundStyle(.secondary)

            Text("My Journey History")
              .font(.title2)
              .fontWeight(.bold)
              .foregroundStyle(.primary)
          }
          .padding(.top, 20)

          Divider()

          HStack(alignment: .bottom) {
            Text("\(stats.totalJourneys)")
              .font(.system(size: 64, weight: .bold))
            Text("perjalanan")
              .font(.title3)
              .fontWeight(.medium)
              .foregroundStyle(.secondary)
              .padding(.bottom, 12)
          }

          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 24) {
            ShareStatItem(title: "Jarak", value: "\(Int(stats.totalDistanceKm)) km")
            ShareStatItem(title: "Waktu", value: "\(stats.totalDurationMinutes / 60) jam")
            ShareStatItem(title: "Stasiun", value: "\(stats.uniqueStationsCount)")
            ShareStatItem(title: "Kereta", value: "\(stats.uniqueTrainsCount)")
          }

          Spacer()

          // Footer
          HStack {
            Image(systemName: "train.side.front.car")
            Text("Kreta App")
              .fontWeight(.semibold)
            Spacer()
            Text(Date().formatted(date: .abbreviated, time: .omitted))
              .foregroundStyle(.secondary)
          }
          .font(.caption)
          .padding(.bottom, 40)
        }
        .padding(.horizontal, 32)
        .background(Color(uiColor: UIColor.systemBackground))
      }
    }
    .frame(width: 414, height: 896)  // iPhone 11 Pro Max / generic large phone size for reference
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .shadow(radius: 20)
  }
}

struct ShareStatItem: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading) {
      Text(title.uppercased())
        .font(.caption2)
        .fontWeight(.bold)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.title3)
        .fontWeight(.bold)
        .foregroundStyle(.primary)
    }
  }
}
