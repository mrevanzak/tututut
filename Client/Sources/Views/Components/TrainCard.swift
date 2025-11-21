//
//  TrainSheet.swift
//  kreta
//
//  Created by Gilang Banyu Biru Erassunu on 25/10/25.
//

import SwiftUI

struct TrainCard: View {
  @Environment(Router.self) private var router
  @Environment(\.colorScheme) private var colorScheme
  let train: ProjectedTrain
  let journeyData: TrainJourneyData?
  let onDelete: () -> Void
  var compactMode: Bool = false

  @State private var showingDeleteAlert = false

  var body: some View {
    Group {
      if compactMode {
        compactView
      } else {
        fullSheetView
      }
    }.onAppear {
      if trainStatus() == .sudahTiba {
        router.navigate(
          to: .fullScreen(
            .arrival(stationCode: arrivalStationCode, stationName: arrivalStationName)))
      }
    }
  }

  // MARK: - Compact Mode View

  private var compactView: some View {
    // Journey details with train image in HStack
    HStack(alignment: .center, spacing: 10) {
      // Departure station
      VStack(spacing: 4) {
        Text(departureStationCode)
          .font(.title)
          .bold()

        Text(departureStationName)
          .font(.subheadline)
          .lineLimit(1)
          .minimumScaleFactor(0.7)

        Text(formatTime(departureTime))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)

      // Train icon - aligned with station codes
      VStack(spacing: 12) {

        Image(colorScheme.keretaName)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: 115, height: 20)
          .frame(maxWidth: .infinity)

        ZStack(alignment: .top) {
          Image(colorScheme.keretaBackground)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: 24)
            .offset(y: -4)

          durationStatusView

        }
      }
      .frame(minWidth: 155)

      // Arrival station
      VStack(spacing: 4) {
        Text(arrivalStationCode)
          .font(.title)
          .bold()

        Text(arrivalStationName)
          .font(.subheadline)
          .lineLimit(1)
          .minimumScaleFactor(0.7)

        Text(formatTime(arrivalTime))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 16)
  }

  // MARK: - Full Sheet View

  private var fullSheetView: some View {
    VStack(spacing: 0) {
      // Train image at top of journey details
      Image(colorScheme.keretaName)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 115, height: 20)
        .padding(.top, 4)

      // Journey details without train image
      HStack(spacing: 10) {
        // Departure station
        VStack(spacing: 4) {
          Text(departureStationCode)
            .font(.title)
            .bold()

          Text(departureStationName)
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

          Text(formatTime(departureTime))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)

        // Duration (separated text)
        VStack(spacing: 4) {
          ZStack(alignment: .top) {
            Image(colorScheme.keretaBackground)
              .resizable()
              .scaledToFill()
              .frame(maxWidth: .infinity, maxHeight: 24)
              .offset(y: lowerBackgroundOffset)

            durationStatusView

          }
        }
        .frame(minWidth: 155)

        // Arrival station
        VStack(spacing: 4) {
          Text(arrivalStationCode)
            .font(.title)
            .bold()

          Text(arrivalStationName)
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

          Text(formatTime(arrivalTime))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
      }
      .frame(maxWidth: .infinity)

      // Share button at bottom
      Button(action: {
        // Share action
        router.navigate(to: .sheet(.shareJourney))
      }) {
        HStack(spacing: 8) {
          Image(systemName: "square.and.arrow.up")
          Text("Share Perjalanan")
            .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
        .glassEffect(.regular.tint(.backgroundPrimary.opacity(0.15)))
        .foregroundStyle(.textSecondary)
        .cornerRadius(20)
      }
      .padding(.top)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  @ViewBuilder
  private var durationStatusView: some View {
    switch trainStatus() {
    case .sedangBerjalan:
      VStack(spacing: 4) {
        Text("Tiba dalam")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Text(formattedDurationTime())
          .font(.headline)
          .fontWeight(.bold)
          .foregroundStyle(.blue)
          .multilineTextAlignment(.center)
      }

    case .belumBerangkat:
      Text("Kereta belum berangkat")
        .font(.subheadline)
        .fontWeight(.bold)
        .foregroundStyle(.blue)
        .multilineTextAlignment(.center)

    case .sudahTiba:
      Text("Sudah tiba")
        .font(.subheadline)
        .fontWeight(.bold)
        .foregroundStyle(.blue)
        .multilineTextAlignment(.center)

    case .tidakTersedia:
      Text("Waktu tidak tersedia")
        .font(.subheadline)
        .fontWeight(.bold)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
  }

  // MARK: - Computed Properties

  /// Use user-selected departure station if available, otherwise use current segment
  private var departureStationCode: String {
    journeyData?.userSelectedFromStation.code ?? train.fromStation?.code ?? "--"
  }

  private var departureStationName: String {
    journeyData?.userSelectedFromStation.name ?? train.fromStation?.name ?? "Unknown"
  }

  private var departureTime: Date? {
    journeyData?.userSelectedDepartureTime ?? train.journeyDeparture
  }

  /// Use user-selected arrival station if available, otherwise use current segment
  private var arrivalStationCode: String {
    journeyData?.userSelectedToStation.code ?? train.toStation?.code ?? "--"
  }

  private var arrivalStationName: String {
    journeyData?.userSelectedToStation.name ?? train.toStation?.name ?? "Unknown"
  }

  private var arrivalTime: Date? {
    journeyData?.userSelectedArrivalTime ?? train.journeyArrival
  }

  // MARK: - Helper Functions

  // Helper function to format duration time only (without "Tiba dalam" prefix)
  private func formattedDurationTime() -> String {
    guard let departure = departureTime, let arrival = arrivalTime else {
      return "Waktu tidak tersedia"
    }

    let now = Date()

    // Check if train hasn't departed yet
    if now < departure {
      return "Kereta belum berangkat"
    }

    // Check if train has already arrived
    if now >= arrival {
      return "Sudah Tiba"
    }

    // Calculate time remaining until arrival
    let timeInterval = arrival.timeIntervalSince(now)
    let totalMinutes = Int(timeInterval / 60)

    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    if hours > 0 && minutes > 0 {
      return "\(hours) Jam \(minutes) Menit"
    } else if hours > 0 {
      return "\(hours) Jam"
    } else if minutes > 0 {
      return "\(minutes) Menit"
    } else {
      return "Sebentar Lagi"
    }
  }

  private func formatTime(_ date: Date?) -> String {
    guard let date else { return "--:--" }
    return date.formatted(.dateTime.hour().minute())
  }

  private func trainStatus() -> TrainStatus {
    guard let departure = departureTime,
      let arrival = arrivalTime
    else {
      return .tidakTersedia
    }

    let now = Date()

    if now < departure {
      return .belumBerangkat
    }

    if now >= arrival {
      return .sudahTiba
    }

    return .sedangBerjalan
  }

  private var lowerBackgroundOffset: CGFloat {
    switch trainStatus() {
    case .sudahTiba:
      return -16
    case .belumBerangkat:
      return -9
    case .sedangBerjalan:
      return -7
    case .tidakTersedia:
      return -7
    }
  }

  enum TrainStatus {
    case belumBerangkat
    case sedangBerjalan
    case sudahTiba
    case tidakTersedia
  }

}

#Preview {
  let stations = [
    Station(
      code: "GMR",
      name: "Gambir",
      position: Position(latitude: -6.1774, longitude: 106.8306),
      city: "Jakarta Selatan"
    ),
    Station(
      code: "JNG",
      name: "Jatinegara",
      position: Position(latitude: -6.2149, longitude: 106.8707),
      city: "Jakarta Selatan"
    ),
  ]

  let train = ProjectedTrain(
    id: "T1-0",
    code: "T1",
    name: "Sample Express",
    position: Position(latitude: -6.1950, longitude: 106.8500),
    moving: true,
    bearing: 45,
    routeIdentifier: "L1",
    speedKph: 60,
    fromStation: stations[0],
    toStation: stations[1],
    segmentDeparture: Date().addingTimeInterval(-15 * 60),
    segmentArrival: Date().addingTimeInterval(15 * 60),
    progress: 0.5,
    journeyDeparture: Date().addingTimeInterval(-60 * 60),
    journeyArrival: Date().addingTimeInterval(2 * 60 * 60)
  )

  ZStack {
    Color.gray.opacity(0.2)
      .ignoresSafeArea()

    TrainCard(train: train, journeyData: nil, onDelete: {}, compactMode: false)
      .padding()
  }
}
