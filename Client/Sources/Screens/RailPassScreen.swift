import MapKit
import SwiftUI

struct RailPassScreen: View {
  @Environment(TrainMapStore.self) private var mapStore
  @Environment(\.dismiss) private var dismiss
  @Environment(\.displayScale) private var displayScale

  @State private var viewModel = RailPassViewModel()
  @State private var showShareSheet = false
  @State private var renderedImage: UIImage?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          // Map Section
          if !viewModel.journeys.isEmpty {
            RailPassMapView(routes: filteredRoutes, stations: filteredStations)
              .frame(height: 300)
              .cornerRadius(16)
              .shadow(radius: 5)
              .padding(.horizontal)
          }

          // Stats Section
          RailPassStatsView(stats: viewModel.stats)
            .padding(.horizontal)

          // Recent Journeys List
          VStack(alignment: .leading, spacing: 16) {
            Text("Riwayat Perjalanan")
              .font(.headline)
              .padding(.horizontal)

            if viewModel.isLoading {
              ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
            } else if viewModel.journeys.isEmpty {
              ContentUnavailableView(
                "Belum Ada Perjalanan",
                systemImage: "train.side.front.car",
                description: Text("Mulai perjalanan keretamu untuk melihat statistik di sini.")
              )
            } else {
              LazyVStack(spacing: 12) {
                ForEach(viewModel.journeys) { journey in
                  JourneyHistoryRow(journey: journey)
                }
              }
              .padding(.horizontal)
            }
          }
        }
        .padding(.vertical)
      }
      .navigationTitle("Rail Pass")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            renderAndShare()
          } label: {
            Image(systemName: "square.and.arrow.up")
          }
          .disabled(viewModel.journeys.isEmpty)
        }

        ToolbarItem(placement: .topBarLeading) {
          Button("Tutup") {
            dismiss()
          }
        }
      }
      .task {
        // Load data when view appears
        await viewModel.loadData(stations: mapStore.stations)
      }
      .sheet(isPresented: $showShareSheet) {
        if let image = renderedImage {
          ShareSheet(activityItems: [image])
        }
      }
    }
  }

  // MARK: - Helpers

  private var filteredRoutes: [Route] {
    let routeIds = Set(viewModel.journeys.flatMap { $0.routeIds }.compactMap { $0 })
    return mapStore.routes.filter { routeIds.contains($0.id) }
  }

  private var filteredStations: [Station] {
    let stationCodes = Set(viewModel.journeys.flatMap { [$0.fromStationCode, $0.toStationCode] })
    return mapStore.stations.filter { stationCodes.contains($0.code) }
  }

  @MainActor
  private func renderAndShare() {
    let shareView = RailPassShareView(
      stats: viewModel.stats,
      routes: filteredRoutes,
      stations: filteredStations
    )

    let renderer = ImageRenderer(content: shareView)
    renderer.scale = displayScale

    if let uiImage = renderer.uiImage,
      let imageData = uiImage.pngData()
    {
      openInInstagram(imageData: imageData)
    }
  }

  private func openInInstagram(imageData: Data) {
    let pasteboardItems = [
      "com.instagram.sharedSticker.backgroundImage": imageData
    ]
    UIPasteboard.general.setItems(
      [pasteboardItems],
      options: [
        .expirationDate: Date().addingTimeInterval(60 * 5)
      ])

    let instagramURL = URL(string: "instagram-stories://share?source_application=com.kreta.app")!

    if UIApplication.shared.canOpenURL(instagramURL) {
      UIApplication.shared.open(instagramURL)
    } else {
      // Fallback to system share sheet if Instagram is not installed
      if let image = UIImage(data: imageData) {
        renderedImage = image
        showShareSheet = true
      }
    }
  }
}

struct JourneyHistoryRow: View {
  let journey: CompletedJourney

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(journey.trainName)
          .font(.headline)
        Text("\(journey.fromStationName) → \(journey.toStationName)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 4) {
        Text(journey.selectedDate.formatted(date: .abbreviated, time: .omitted))
          .font(.caption)
          .foregroundStyle(.secondary)

        if journey.journeyDurationMinutes > 0 {
          Text("\(journey.journeyDurationMinutes / 60)j \(journey.journeyDurationMinutes % 60)m")
            .font(.caption)
            .fontWeight(.medium)
        }
      }
    }
    .padding()
    .background(Color(uiColor: .secondarySystemBackground))
    .cornerRadius(12)
  }
}

struct ShareSheet: UIViewControllerRepresentable {
  var activityItems: [Any]
  var applicationActivities: [UIActivity]? = nil

  func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(
      activityItems: activityItems, applicationActivities: applicationActivities)
    return controller
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
