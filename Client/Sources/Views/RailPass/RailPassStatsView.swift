import SwiftUI

struct RailPassStatsView: View {
  let stats: RailPassStats

  var body: some View {
    VStack(spacing: 12) {
      // Main Stat: Total Journeys
      HStack {
        VStack(alignment: .leading) {
          Text("Total Perjalanan")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text("\(stats.totalJourneys)")
            .font(.system(size: 36, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
        }
        Spacer()
        // Icon or graphic could go here
        Image(systemName: "train.side.front.car")
          .font(.system(size: 32))
          .foregroundStyle(.blue.gradient)
          .opacity(0.8)
      }
      .padding()
      .background(Color(uiColor: .secondarySystemBackground))
      .cornerRadius(16)

      // Grid for other stats
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        StatCard(
          title: "Jarak Tempuh",
          value: formatDistance(stats.totalDistanceKm),
          unit: "km",
          icon: "map"
        )

        StatCard(
          title: "Waktu Perjalanan",
          value: formatDuration(stats.totalDurationMinutes),
          unit: "",
          icon: "clock"
        )

        StatCard(
          title: "Stasiun Dikunjungi",
          value: "\(stats.uniqueStationsCount)",
          unit: "stasiun",
          icon: "building.columns"
        )

        StatCard(
          title: "Kereta Dinaiki",
          value: "\(stats.uniqueTrainsCount)",
          unit: "kereta",
          icon: "tram"
        )
      }
    }
  }

  private func formatDistance(_ km: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 1
    return formatter.string(from: NSNumber(value: km)) ?? "\(Int(km))"
  }

  private func formatDuration(_ minutes: Int) -> String {
    let hours = minutes / 60
    let mins = minutes % 60
    if hours > 0 {
      return "\(hours)j \(mins)m"
    }
    return "\(mins)m"
  }
}

struct StatCard: View {
  let title: String
  let value: String
  let unit: String
  let icon: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: icon)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(value)
          .font(.title2)
          .fontWeight(.bold)
          .foregroundStyle(.primary)

        if !unit.isEmpty {
          Text(unit)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(uiColor: .secondarySystemBackground))
    .cornerRadius(16)
  }
}

#Preview {
  RailPassStatsView(
    stats: RailPassStats(
      totalJourneys: 12,
      totalDistanceKm: 1250.5,
      totalDurationMinutes: 840,
      uniqueStationsCount: 8,
      uniqueTrainsCount: 5
    )
  )
  .padding()
}
