//
//  StationScheduleView.swift
//  kreta
//
//  Created by Gilang Banyu Biru Erassunu on 18/11/25.
//

import SwiftUI

// MARK: - Grouped Train Data

struct GroupedTrainSchedule: Identifiable {
  let id: String  // trainCode + origin + destination
  let trainCode: String
  let trainName: String
  let origin: String
  let destination: String
  let originCode: String
  let destinationCode: String
  let schedules: [TrainStopService.TrainAtStation]
  
  var nextDeparture: TrainStopService.TrainAtStation? {
    schedules.first { train in
      guard let departureTime = train.departureTime else { return false }
      return parseTime(departureTime) ?? Date.distantPast > Date()
    }
  }
  
  var upcomingCount: Int {
    schedules.filter { train in
      guard let departureTime = train.departureTime else { return false }
      return parseTime(departureTime) ?? Date.distantPast > Date()
    }.count
  }
  
  private func parseTime(_ timeString: String) -> Date? {
    let components = timeString.split(separator: ":")
    guard components.count >= 2,
          let hour = Int(components[0]),
          let minute = Int(components[1])
    else { return nil }
    
    let calendar = Calendar.current
    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date())
  }
}

struct StationScheduleView: View {
  @Environment(TrainMapStore.self) private var mapStore
  @Environment(\.dismiss) private var dismiss
  @Environment(\.showToast) private var showToast
  @Environment(Router.self) private var router
  
  @State private var trains: [TrainStopService.TrainAtStation] = []
  @State private var groupedTrains: [GroupedTrainSchedule] = []
  @State private var isLoading: Bool = false
  @State private var expandedGroups: Set<String> = []
  
  private let trainStopService = TrainStopService()
  private let journeyService = JourneyService()
  
  var body: some View {
    VStack(spacing: 0) {
      headerView
      
      if let station = mapStore.selectedStationForSchedule {
        contentView(for: station)
      } else {
        emptyStateView
      }
    }
    .background(.backgroundPrimary)
    .task {
      await loadTrainSchedule()
    }
  }
  
  // MARK: - Header View
  
  private var headerView: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        if let station = mapStore.selectedStationForSchedule {
          Text("Stasiun")
            .font(.title2.bold())
          
          Text("\(station.name) (\(station.code))")
            .font(.title2.bold())
            .foregroundStyle(.highlight)
          
          Text("Jadwal kereta yang melintas di \(station.code)")
            .font(.subheadline)
            .foregroundStyle(.sublime)
        } else {
          Text("Jadwal Stasiun")
            .font(.title2.bold())
            .foregroundStyle(.primary)
        }
      }
      
      Spacer()
      
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .symbolRenderingMode(.palette)
          .foregroundStyle(.textSecondary, .primary)
          .font(.largeTitle)
      }
      .frame(width: 44, height: 44)
      .foregroundStyle(.backgroundSecondary)
      .glassEffect(.regular.tint(.backgroundSecondary))
    }
    .padding()
    .background(.backgroundPrimary)
  }
  
  // MARK: - Content View
  
  @ViewBuilder
  private func contentView(for station: Station) -> some View {
    if isLoading {
      loadingView
    } else if groupedTrains.isEmpty {
      noTrainsView
    } else {
      trainGroupListView
    }
  }
  
  private var loadingView: some View {
    VStack {
      Spacer()
      ProgressView()
        .controlSize(.large)
      Text("Memuat jadwal kereta...")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
      Spacer()
    }
  }
  
  private var noTrainsView: some View {
    VStack(spacing: 16) {
      Spacer()
      
      Image(systemName: "train.side.front.car")
        .font(.system(size: 48))
        .foregroundStyle(.secondary)
      
      Text("Tidak Ada Kereta")
        .font(.title3.bold())
        .foregroundStyle(.primary)
      
      Text("Tidak ada kereta yang berhenti di stasiun ini")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
      
      Spacer()
    }
  }
  
  private var trainGroupListView: some View {
    ScrollView {
      LazyVStack(spacing: 12) {
        ForEach(groupedTrains) { group in
          TrainGroupCard(
            group: group,
            isExpanded: expandedGroups.contains(group.id),
            onToggleExpand: {
              withAnimation(.spring(response: 0.3)) {
                if expandedGroups.contains(group.id) {
                  expandedGroups.remove(group.id)
                } else {
                  expandedGroups.insert(group.id)
                }
              }
            },
            onSelectSchedule: { train in
              handleTrainSelection(train)
            }
          )
        }
      }
      .padding()
    }
  }
  
  private var emptyStateView: some View {
    ContentUnavailableView(
      "Tidak Ada Stasiun Dipilih",
      systemImage: "mappin.slash",
      description: Text("Silakan pilih stasiun terlebih dahulu")
    )
  }
  
  // MARK: - Actions
  
  private func loadTrainSchedule() async {
    guard let station = mapStore.selectedStationForSchedule else { return }
    guard let stationId = station.id else { return }
    
    isLoading = true
    defer { isLoading = false }
    
    do {
      trains = try await trainStopService.getTrainsAtStation(stationId: stationId).filter { !$0.isDestination }
      
      updateGroupedTrains()
    } catch {
      showToast("Gagal memuat jadwal kereta")
      print("Failed to load train schedule: \(error)")
    }
  }
  
  private func updateGroupedTrains() {
    // Group by train code + origin + destination (the complete route)
    let grouped = Dictionary(grouping: trains) { train in
      "\(train.trainName)_\(train.origin)_\(train.destination)"
    }
    
    groupedTrains = grouped.map { key, schedules in
      let first = schedules[0]
      return GroupedTrainSchedule(
        id: key,
        trainCode: first.trainCode,
        trainName: first.trainName,
        origin: first.origin,
        destination: first.destination,
        originCode: first.originStationCode,
        destinationCode: first.destinationStationCode,
        schedules: schedules.sorted { (a, b) in
          let timeA = a.departureTime ?? a.arrivalTime ?? ""
          let timeB = b.departureTime ?? b.arrivalTime ?? ""
          return timeA < timeB
        }
      )
    }.sorted { a, b in
      // Sort by train name first, then by origin-destination
      if a.trainName != b.trainName {
        return a.trainName < b.trainName
      }
      return a.origin < b.origin
      //      return "\(a.origin)-\(a.destination)" < "\(b.origin)-\(b.destination)"
    }
  }
  
  private func parseTime(_ timeString: String) -> Date? {
    let components = timeString.split(separator: ":")
    guard components.count >= 2,
          let hour = Int(components[0]),
          let minute = Int(components[1])
    else { return nil }
    
    let calendar = Calendar.current
    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date())
  }
  
  private func handleTrainSelection(_ train: TrainStopService.TrainAtStation) {
    Task {
      do {
        // Get the selected station as departure
        guard let currentStation = mapStore.selectedStationForSchedule,
              let currentStationId = currentStation.id else {
          showToast("Stasiun tidak ditemukan")
          return
        }
        
        // Determine if current station is origin or destination for this train
        // If it's the destination, user can't board here
        if train.isDestination {
          showToast("Kereta ini berakhir di stasiun ini")
          return
        }
        
        // Find a suitable destination station from the train's route
        guard let schedule = try await trainStopService.getTrainSchedule(trainCode: train.trainCode) else {
          showToast("Gagal memuat data kereta")
          return
        }
        
        // Find current station in the schedule
        guard let currentStopIndex = schedule.stops.firstIndex(where: { $0.stationId == currentStationId }) else {
          showToast("Stasiun tidak ditemukan dalam rute kereta")
          return
        }
        
        // Get all stations after current station
        let stationsAhead = schedule.stops.suffix(from: currentStopIndex + 1)
        
        // Find the final destination (last stop)
        guard let finalDestination = stationsAhead.last else {
          showToast("Tidak ada stasiun tujuan tersedia")
          return
        }
        
        // Use journey service to fetch projected train data
        let selectedDate = Date()  // Use today's date
        
        let availableTrains = try await journeyService.fetchProjectedForRoute(
          departureStationId: currentStationId,
          arrivalStationId: finalDestination.stationId,
          selectedDate: selectedDate
        )
        
        // Find the specific train by matching trainId
        guard let matchingTrain = availableTrains.first(where: { item in
          item.trainId == train.trainId
        }) else {
          showToast("Data kereta tidak ditemukan")
          return
        }
        
        // Build journey data similar to AddTrainView
        let stationsById = StationLookupHelper.buildStationsById(mapStore.stations)
        
        guard let fromStation = stationsById[currentStationId],
              let toStation = stationsById[finalDestination.stationId] else {
          showToast("Stasiun tidak ditemukan")
          return
        }
        
        // Fetch journey segments
        let segments = try await journeyService.fetchSegmentsForTrain(
          trainId: matchingTrain.trainId,
          selectedDate: selectedDate
        )
        
        // Build journey segments and collect stations
        let (journeySegments, allStationsInJourney) = JourneyDataBuilder.buildSegmentsAndStations(
          from: segments,
          stationsById: stationsById
        )
        
        // Build journey data
        let journeyData = JourneyDataBuilder.buildTrainJourneyData(
          trainId: matchingTrain.trainId,
          segments: journeySegments,
          allStations: allStationsInJourney,
          fromStation: fromStation,
          toStation: toStation,
          userSelectedDepartureTime: matchingTrain.segmentDeparture,
          userSelectedArrivalTime: matchingTrain.segmentArrival,
          selectedDate: selectedDate
        )
        
        // Create projected train
        let projectedTrain = ProjectedTrain(
          id: matchingTrain.id,
          code: matchingTrain.code,
          name: matchingTrain.name,
          position: Position(
            latitude: fromStation.position.latitude,
            longitude: fromStation.position.longitude
          ),
          moving: false,
          bearing: nil,
          routeIdentifier: matchingTrain.routeId,
          speedKph: nil,
          fromStation: fromStation,
          toStation: toStation,
          segmentDeparture: matchingTrain.segmentDeparture,
          segmentArrival: matchingTrain.segmentArrival,
          progress: nil,
          journeyDeparture: matchingTrain.segmentDeparture,
          journeyArrival: matchingTrain.segmentArrival
        )
        
        // Check if alarm setup is needed
        if !AlarmPreferences.shared.hasCompletedInitialSetup {
          mapStore.pendingTrainForAlarmConfiguration = projectedTrain
          mapStore.pendingJourneyDataForAlarmConfiguration = journeyData
          dismiss()
          router.navigate(to: .sheet(.alarmConfiguration))
        } else {
          // Start tracking immediately
          try await mapStore.selectTrain(
            projectedTrain,
            journeyData: journeyData,
            alarmOffsetMinutes: nil
          )
          dismiss()
          showToast("Melacak \(train.trainName) ke \(toStation.name)")
        }
        
      } catch {
        showToast("Gagal memuat data kereta")
        print("Failed to load train data: \(error)")
      }
    }
  }
  
  private func formatTimeFromDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }
}

// MARK: - Train Group Card

private struct TrainGroupCard: View {
  let group: GroupedTrainSchedule
  let isExpanded: Bool
  let onToggleExpand: () -> Void
  let onSelectSchedule: (TrainStopService.TrainAtStation) -> Void
  
  var body: some View {
    VStack(spacing: 0) {
      // Header - always visible
      Button(action: onToggleExpand) {
        VStack(spacing: 12) {
          // Train icon
          
          VStack(alignment: .leading, spacing: 4) {
            // Train name and code
            HStack(alignment: .center, spacing: 8) {
              Text(group.trainName)
                .font(.title3.bold())
                .foregroundStyle(.textSecondary)
              
              Text(group.trainCode)
                .font(.callout)
                .foregroundStyle(.sublime)
              
              Spacer()
              
              // Expand indicator
              VStack {
                Spacer() // pushes image down
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.tertiary)
              }
            }
            
            // Full route: Origin → Destination
            HStack(alignment: .lastTextBaseline, spacing: 4) {
              Text(group.originCode)
                .font(.subheadline)
                .foregroundStyle(.highlight)
                .lineLimit(1)
              
              Image(systemName: "arrow.right.square.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.backgroundPrimary, .highlight)
                .font(.subheadline)
              
              Text(group.destinationCode)
                .font(.subheadline)
                .foregroundStyle(.highlight)
                .lineLimit(1)
              
              if let next = group.nextDeparture?.departureTime {
                Text("Berikutnya: \(formatTime(next))")
                  .font(.caption2)
                  .foregroundStyle(.sublime)
              }
              
              Spacer()
              
              // Schedule Count
              HStack(spacing: 2) {
                Image(systemName: "tram.circle.fill")
                  .font(.caption2)
                  .foregroundStyle(.sublime)
  
                Text("\(group.schedules.count) jadwal")
                  .font(.caption2)
                  .foregroundStyle(.sublime)
              }
            }
          }
        }
        .padding(16)
      }
      .buttonStyle(.plain)
      
      // Expanded schedules
      if isExpanded {
        Divider()
          .padding(.horizontal, 16)
        
        VStack(spacing: 0) {
          ForEach(Array(group.schedules.enumerated()), id: \.element.id) { index, schedule in
            ScheduleTimeRow(
              schedule: schedule,
              isLast: index == group.schedules.count - 1,
              onTap: { onSelectSchedule(schedule) }
            )
          }
        }
        .padding(.vertical, 8)
      }
    }
    .background(Color.backgroundSecondary)
    .cornerRadius(12)
  }
  
  private func formatTime(_ timeString: String) -> String {
    let components = timeString.split(separator: ":")
    if components.count >= 2 {
      return "\(components[0]):\(components[1])"
    }
    return timeString
  }
}

// MARK: - Schedule Time Row

private struct ScheduleTimeRow: View {
  let schedule: TrainStopService.TrainAtStation
  let isLast: Bool
  let onTap: () -> Void
  
  @State private var isPast: Bool = false
  
  var body: some View {
    Button(action: onTap) {
      VStack(spacing: 0) {
        HStack(spacing: 12) {
          // Time badge
          VStack(spacing: 2) {
            if let departureTime = schedule.departureTime {
              Text(formatTime(departureTime))
                .font(.system(.body, design: .rounded).monospacedDigit().weight(.semibold))
                .foregroundStyle(isPast ? .tertiary : .primary)
            }
            
            Text(schedule.isOrigin ? "Awal" : schedule.isDestination ? "Akhir" : "Berhenti")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
          .frame(width: 80, alignment: .leading)
          
          // Time indicator
          VStack(spacing: 4) {
            Circle()
              .fill(isPast ? Color.gray.opacity(0.3) : Color.highlight)
              .frame(width: 12, height: 12)
            
            if !isLast {
              Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
            }
          }
          .frame(height: isLast ? 12 : 50)
          
          // Details
          VStack(alignment: .leading, spacing: 4) {
            if let arrivalTime = schedule.arrivalTime,
               schedule.arrivalTime != schedule.departureTime {
              Text("Tiba: \(formatTime(arrivalTime))")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            if isPast {
              Text("Telah berangkat")
                .font(.caption)
                .foregroundStyle(.tertiary)
            } else {
              Text("Tap untuk lacak")
                .font(.caption.weight(.medium))
                .foregroundStyle(.highlight)
            }
          }
          
          Spacer()
          
          if !isPast {
            Image(systemName: "arrow.right.circle.fill")
              .font(.title3)
              .foregroundStyle(.highlight)
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
      }
    }
    .buttonStyle(.plain)
    .disabled(isPast)
    .onAppear {
      checkIfPast()
    }
  }
  
  private func formatTime(_ timeString: String) -> String {
    let components = timeString.split(separator: ":")
    if components.count >= 2 {
      return "\(components[0]):\(components[1])"
    }
    return timeString
  }
  
  private func checkIfPast() {
    guard let departureTime = schedule.departureTime else {
      isPast = false
      return
    }
    print("debug time: \(departureTime)")
    
    let components = departureTime.split(separator: ":")
    guard components.count == 3,
          let hour = Int(components[0]),
          let minute = Int(components[1]),
          let second = Int(components[2]) else {
      isPast = false
      return
    }
    
    let calendar = Calendar.current
    if let scheduleTime = calendar.date(
      bySettingHour: hour,
      minute: minute,
      second: second,
      of: Date()
    ) {
      isPast = scheduleTime < Date()
    }
  }
  
}

// MARK: - Train Schedule Row (Legacy - kept for reference)

private struct TrainScheduleRow: View {
  let train: TrainStopService.TrainAtStation
  let isSelected: Bool
  let onTap: () -> Void
  
  var body: some View {
    Button(action: onTap) {
      VStack(spacing: 0) {
        HStack(alignment: .top, spacing: 12) {
          // Train icon
          ZStack {
            Circle()
              .fill(Color.highlight.opacity(0.1))
              .frame(width: 48, height: 48)
            
            Image(systemName: "tram.fill")
              .font(.title3)
              .foregroundStyle(.highlight)
          }
          
          VStack(alignment: .leading, spacing: 4) {
            // Train name and code
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(train.trainName)
                .font(.headline)
                .foregroundStyle(.primary)
              
              Text(train.trainCode)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            }
            
            // Route
            HStack(spacing: 4) {
              Text(train.origin)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
              
              Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
              
              Text(train.destination)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            
            // Time information
            HStack(spacing: 16) {
              if let arrivalTime = train.arrivalTime {
                TimeLabel(label: "Tiba", time: arrivalTime)
              }
              
              if let departureTime = train.departureTime {
                TimeLabel(label: "Berangkat", time: departureTime)
              }
            }
            .padding(.top, 4)
          }
          
          Spacer()
          
          // Chevron indicator
          Image(systemName: "chevron.right")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
        .padding(16)
      }
      .background(isSelected ? Color.highlight.opacity(0.05) : Color.backgroundSecondary)
      .cornerRadius(12)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Time Label

private struct TimeLabel: View {
  let label: String
  let time: String
  
  var body: some View {
    HStack(spacing: 4) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.tertiary)
      
      Text(formattedTime)
        .font(.caption.monospacedDigit().weight(.medium))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Color.primary.opacity(0.05))
    .cornerRadius(6)
  }
  
  private var formattedTime: String {
    // Time is in format "HH:MM:SS", we just want "HH:MM"
    let components = time.split(separator: ":")
    if components.count >= 2 {
      return "\(components[0]):\(components[1])"
    }
    return time
  }
}

// MARK: - Preview

#Preview("Station Schedule View") {
  let store = TrainMapStore.preview
  store.selectedStationForSchedule = Station(
    id: "102",
    code: "MRI",
    name: "Manggarai",
    position: Position(latitude: -6.2102, longitude: 106.8499),
    city: "Jakarta"
  )
  
  return StationScheduleView()
    .environment(Router.previewRouter())
    .environment(store)
    .environment(\.showToast, .preview)
}
