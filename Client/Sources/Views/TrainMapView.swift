import MapKit
import SwiftUI

struct TrainMapView: View {
  @Environment(TrainMapStore.self) private var mapStore
  @Environment(\.showToast) private var showToast

  @State var isFollowing: Bool = true
  @State var focusTrigger: Bool = false
  @State private var userHasPanned: Bool = false
  @State private var cameraPosition: MapCameraPosition = .automatic
  @State private var visibleRegionSpan: MKCoordinateSpan?
  @State private var trainStops: [TrainStopService.TrainStop] = []
  @State private var isLoadingStops: Bool = false

  private let trainStopService = TrainStopService()

  private var isTrackingTrain: Bool {
    mapStore.liveTrainPosition != nil
  }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Map(position: $cameraPosition) {
        // Routes
        ForEach(filteredRoutes) { route in
          let coords = route.coordinates
          if coords.count > 1 {
            MapPolyline(coordinates: coords)
              .stroke(.blue, lineWidth: 3)
          }
        }
        if isTrackingTrain || (!isTrackingTrain && isStationZoomVisible) {
          ForEach(filteredStations) { station in
            Annotation(station.name, coordinate: station.coordinate) {
              ZStack {
                Circle()
                  .fill(Color.blue)
                  .frame(width: 32, height: 32)
                  .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
                Circle()
                  .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                  .frame(width: 32, height: 32)
                Text(station.code)
                  .font(.system(size: 12, weight: .bold, design: .rounded))
                  .foregroundStyle(.white)
                  .minimumScaleFactor(0.6)
                  .lineLimit(1)
                  .padding(.horizontal, 4)
              }
            }
          }
        }
        // Live train(s)
        ForEach(filteredTrains) { train in
          let isMoving = train.moving
          Marker("\(train.name) (\(train.code))", systemImage: "tram.fill", coordinate: train.coordinate)
            .tint(isMoving ? .blue : .red)
        }
      }
      .onMapCameraChange(frequency: .onEnd) { context in
        let region = context.region
        visibleRegionSpan = region.span
      }
      // break follow as soon as user interacts with the map
      .simultaneousGesture(
        DragGesture(minimumDistance: 0).onChanged { _ in
            print("Check Trigger gesture")
          userHasPanned = true
          isFollowing = false
        }
      )

      MapControl(isFollowing: $isFollowing, focusTrigger: $focusTrigger, userHasPanned: $userHasPanned)
    }
    .mapControlVisibility(.hidden)
    .mapStyle(mapStyleForCurrentSelection)

    // Data refresh on timestamp tick
    .onChange(of: mapStore.lastUpdatedAt) { _, lastUpdatedAt in
      guard let lastUpdatedAt else { return }
      Task(priority: .high) {
        do {
          try await mapStore.loadData(at: lastUpdatedAt)
        } catch let error as TrainMapError {
          let msg = "\(error.errorName): \(error.localizedDescription)"
          print("🚂 TrainMapView: \(msg)")
          showToast(msg)
        }
      }
    }

    .onChange(of: mapStore.selectedTrain) { _, newTrain in
      if let train = newTrain {
        Task {
          await loadTrainStops(for: train)
        }
        if isFollowing {
          updateCameraPosition(with: [train])
        }
      } else {
        trainStops = []
      }
    }

    // Follow live position updates
    .onChange(of: mapStore.liveTrainPosition) { _, newPosition in
      if let position = newPosition {
        updateCameraPosition(with: [position])
      }
    }

    // External "focus" poke from the sheet button
    .onChange(of: focusTrigger) { _, newValue in
      if newValue {
        isFollowing = true
        userHasPanned = false
        if let position = mapStore.liveTrainPosition {
          updateCameraPosition(with: [position])
        } else if let train = mapStore.selectedTrain {
          updateCameraPosition(with: [train])
        }
      }
    }

    // Initial load
    .onAppear {
      if let lastUpdatedAt = mapStore.lastUpdatedAt {
        Task(priority: .high) {
          do {
            try await mapStore.loadData(at: lastUpdatedAt)
          } catch let error as TrainMapError {
            let msg = "\(error.errorName): \(error.localizedDescription)"
            print("🚂 TrainMapView: \(msg)")
            showToast(msg)
          }
        }
      }
      
      // Load train stops if there's already a selected train
      if let train = mapStore.selectedTrain {
        Task {
          await loadTrainStops(for: train)
        }
      }

      // Initial focus: if following, prefer live position; else fallback to selected train
      if isFollowing {
        if let position = mapStore.liveTrainPosition {
          updateCameraPosition(with: [position])
        } else if let train = mapStore.selectedTrain {
          updateCameraPosition(with: [train])
        }
      }
    }

    // Auto-reset the trigger after it's consumed so it's fire-once
    .task(id: focusTrigger) {
      if focusTrigger {
        focusTrigger = false
      }
    }
  }

  // MARK: - Train Stop Loading

  private func loadTrainStops(for train: ProjectedTrain) async {
    isLoadingStops = true
    defer { isLoadingStops = false }

    do {
      if let schedule = try await trainStopService.getTrainSchedule(trainCode: train.code) {
        trainStops = schedule.stops
        print("🚂 Loaded \(trainStops.count) stops for train \(train.code)")
      } else {
        trainStops = []
        print("🚂 No schedule found for train \(train.code)")
      }
    } catch {
      print("🚂 Failed to load train stops: \(error)")
      trainStops = []
      showToast("Failed to load train stops")
    }
  }

  // MARK: - Computed filters

  private var filteredRoutes: [Route] {
    guard let journeyData = mapStore.selectedJourneyData else {
      return mapStore.routes
    }
    var routeIds = Set<String>()
    for segment in journeyData.segments {
      if let routeId = segment.routeId {
        routeIds.insert(routeId)
      }
    }
    return mapStore.routes.filter { routeIds.contains($0.id) }
  }

  private var filteredStations: [Station] {
    // If we have train stops from the service, use those
    if !trainStops.isEmpty {
      return mapStore.stations.filter { station in
        trainStops.contains { stop in
          stop.stationId == station.id || stop.stationCode == station.code
        }
      }
    }
    
    // Fallback to journey data if available
    guard let jd = mapStore.selectedJourneyData else {
      return mapStore.stations
    }

    let stopIds = Set(jd.stopStationIds(dwellThreshold: 30))

    return mapStore.stations.filter { st in
      let key = st.id ?? st.code
      return stopIds.contains(key)
    }
  }

  private var filteredTrains: [ProjectedTrain] {
    guard let selectedTrain = mapStore.selectedTrain else { return [] }
    return [mapStore.liveTrainPosition ?? selectedTrain]
  }

  // MARK: - Map style

  private var mapStyleForCurrentSelection: MapStyle {
    switch mapStore.selectedMapStyle {
    case .standard:
      return .standard(
        elevation: .realistic, emphasis: .automatic, pointsOfInterest: .all, showsTraffic: false)
    case .hybrid:
      return .hybrid(elevation: .realistic, pointsOfInterest: .all, showsTraffic: false)
    }
  }

  // MARK: - Camera
  private var isStationZoomVisible: Bool {
    guard let span = visibleRegionSpan else { return false }
    return span.latitudeDelta <= 2.0
  }

  private func updateCameraPosition(with positions: [ProjectedTrain]) {
    guard !positions.isEmpty else { return }
    guard isFollowing else { return }  // respect user exploration

    if positions.count == 1, let train = positions.first {
      withAnimation(.easeInOut(duration: 1.0)) {
        cameraPosition = .region(
          MKCoordinateRegion(
            center: train.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
          )
        )
      }
    } else {
      let coords = positions.map { $0.coordinate }
      updateCameraToFitCoordinates(coords)
    }
  }

  private func updateCameraToFitCoordinates(_ coordinates: [CLLocationCoordinate2D]) {
    guard !coordinates.isEmpty else { return }

    var minLat = coordinates[0].latitude
    var maxLat = coordinates[0].latitude
    var minLon = coordinates[0].longitude
    var maxLon = coordinates[0].longitude

    for coord in coordinates {
      minLat = min(minLat, coord.latitude)
      maxLat = max(maxLat, coord.latitude)
      minLon = min(minLon, coord.longitude)
      maxLon = max(maxLon, coord.longitude)
    }

    let center = CLLocationCoordinate2D(
      latitude: (minLat + maxLat) / 2,
      longitude: (minLon + maxLon) / 2
    )

    let span = MKCoordinateSpan(
      latitudeDelta: max((maxLat - minLat) * 1.5, 0.05),
      longitudeDelta: max((maxLon - minLon) * 1.5, 0.05)
    )

    withAnimation(.easeInOut(duration: 1.0)) {
      cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
  }
}
