//
//  JourneyProgressView.swift
//  kreta
//
//  Created by AI Assistant
//

import SwiftUI

struct JourneyProgressView: View {
  let train: ProjectedTrain
  let journeyData: TrainJourneyData?
  let selectedDate: Date
  let onDelete: () -> Void

  @State private var timelineItems: [StationTimelineItem] = []
  @State private var isLoadingTimeline = true
  @State private var isCardOverContent: Bool = false
  @State private var timer: Timer?
  @State private var hasScrolledToMarker = false  // Track if we've scrolled on appear
  private let trainStopService = TrainStopService()

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: 0) {
      // Train name header - fixed, not scrollable
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 4) {
          Text(train.name)
            .font(.title2)
            .fontWeight(.bold)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.primary)
          Text("(\(train.code))")
            .fontWeight(.bold)
            .foregroundStyle(.sublime)
        }

        Text(selectedDate.formatted(.dateTime.day().month(.wide).year()))
          .font(.subheadline)
          .foregroundStyle(.blue)

      }
      .padding(.top, 20)
      .padding(.bottom, 4)
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.backgroundPrimary)

      // Scrollable content with floating card
      ZStack(alignment: .top) {
        ZStack(alignment: .bottom) {
          ScrollViewReader { proxy in
            ScrollView {
              VStack(spacing: 0) {
                // Top padding to prevent content from hiding under card
                Color.clear
                  .frame(height: 140)

                // Invisible geometry reader to detect scroll position
                GeometryReader { geometry in
                  Color.clear
                    .preference(
                      key: ScrollOffsetPreferenceKey.self,
                      value: geometry.frame(in: .named("scrollView")).minY
                    )
                }
                .frame(height: 0)

                // Timeline list
                if isLoadingTimeline {
                  ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                } else {
                  JourneyTimelineView(items: timelineItems)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 20)
                }
              }
            }
            .contentMargins(.bottom, 24, for: .scrollContent)
            .scrollIndicators(.hidden)
            .coordinateSpace(name: "scrollView")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
              // When content scrolls up past the card area
              isCardOverContent = value < 120
            }
            .onChange(of: timelineItems) { oldValue, newValue in
              // Scroll to current station when timeline loads for the first time
              if !hasScrolledToMarker && !newValue.isEmpty {
                scrollToCurrentStation(proxy: proxy)
              }
            }
          }
          .background(.backgroundPrimary)

          // Bottom gradient fade
          LinearGradient(
            colors: [
              Color.backgroundPrimary.opacity(0),
              Color.backgroundPrimary.opacity(0.7),
              Color.backgroundPrimary.opacity(0.9),
              Color.backgroundPrimary,
            ],
            startPoint: .top,
            endPoint: .bottom
          )
          .frame(height: 80)
          .frame(maxWidth: .infinity)
          .allowsHitTesting(false)
        }

        // Floating train card with gradient background
        VStack(spacing: 0) {
          // Train card with conditional glass effect
          TrainCard(
            train: train,
            journeyData: journeyData,
            onDelete: onDelete,
            compactMode: true
          )
          .if(isCardOverContent) { view in
            view.glassEffect(
              .regular.tint(
                colorScheme == .dark ? .whiteHighlight.opacity(0.1) : .gray.opacity(0.1)
              ),
              in: .rect(cornerRadius: 20)
            )
          }
          .padding(.horizontal, 16)
          .padding(.top, 12)
          .padding(.bottom, 20)
          .background(
            LinearGradient(
              colors: [
                Color.backgroundPrimary,
                Color.backgroundPrimary.opacity(0.9),
                Color.backgroundPrimary.opacity(0.7),
                Color.backgroundPrimary.opacity(0),
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          )

          Spacer()
        }
      }
    }
    .ignoresSafeArea(edges: .bottom)
    .task {
      await loadTimeline()
      startTimer()
    }
    .onDisappear {
      stopTimer()
      hasScrolledToMarker = false  // Reset flag when view disappears
    }
    .onChange(of: train.fromStation?.id) { _, newFromStationId in
      // Don't reload timeline from API - just update states locally
      // All schedule data is already loaded, we just need to update which station is current
      updateCurrentStation(newFromStationId: newFromStationId)
    }
  }

  // MARK: - Helper Methods

  private func startTimer() {
    stopTimer()
    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
      updateTimelineProgress()
    }
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func updateTimelineProgress() {
    // Only update progress values, don't rebuild timeline
    // This prevents jarring refreshes when train arrives at stations
    timelineItems = timelineItems.map { item in
      var updatedItem = item

      // Recalculate progress to next station for all items
      if let currentIndex = timelineItems.firstIndex(where: { $0.id == item.id }),
        currentIndex < timelineItems.count - 1
      {
        let nextItem = timelineItems[currentIndex + 1]
        let currentDeparture = item.departureTime ?? item.arrivalTime
        let nextArrival = nextItem.arrivalTime

        updatedItem.progressToNext = StationTimelineItem.calculateProgress(
          from: currentDeparture,
          to: nextArrival
        )
      }

      return updatedItem
    }
  }

  private func updateCurrentStation(newFromStationId: String?) {
    // Update station states locally without API call
    // All schedule data is already loaded, we just need to update which station is current
    guard let newFromStationId = newFromStationId else { return }

    var foundCurrent = false
    timelineItems = timelineItems.map { item in
      // Determine if this is the new current station
      let isCurrent = item.station.id == newFromStationId && !foundCurrent
      if isCurrent { foundCurrent = true }

      // Determine new state based on position relative to current station
      let newState: StationTimelineItem.StationState
      if foundCurrent && !isCurrent {
        newState = .upcoming
      } else if isCurrent {
        newState = .current
      } else {
        newState = .completed
      }

      // Only create new item if state changed
      guard newState != item.state else { return item }

      return StationTimelineItem(
        id: item.id,
        station: item.station,
        arrivalTime: item.arrivalTime,
        departureTime: item.departureTime,
        state: newState,
        isStop: item.isStop,
        progressToNext: item.progressToNext
      )
    }
  }

  private func scrollToCurrentStation(proxy: ScrollViewProxy) {
    // Find the current station (the one with the train marker)
    if let currentStation = timelineItems.first(where: { $0.state == .current }) {
      // Scroll to it with animation, accounting for the floating card
      withAnimation(.easeInOut(duration: 0.5)) {
        proxy.scrollTo(currentStation.id, anchor: .center)
      }
      hasScrolledToMarker = true
    }
  }

  private func loadTimeline() async {
    isLoadingTimeline = true
    defer { isLoadingTimeline = false }

    // Get current segment's from station to determine progress
    let currentSegmentFromStationId = train.fromStation?.id ?? train.fromStation?.code

    // Use selected date from journey data, or fall back to today
    let selectedDate = journeyData?.selectedDate ?? Date()

    // Get user's destination station ID
    let userDestinationId =
      journeyData?.userSelectedToStation.id ?? journeyData?.userSelectedToStation.code

    // Use new service to get only actual stops
    let items = await StationTimelineItem.buildTimelineFromStops(
      trainCode: train.code,
      currentSegmentFromStationId: currentSegmentFromStationId,
      trainStopService: trainStopService,
      selectedDate: selectedDate,
      userDestinationStationId: userDestinationId
    )

    timelineItems = items
  }
}

// MARK: - Preview

#Preview {
  let stations = [
    Station(
      code: "GMR",
      name: "Gambir",
      position: Position(latitude: -6.1774, longitude: 106.8306),
      city: "Jakarta Pusat"
    ),
    Station(
      code: "JNG",
      name: "Jatinegara",
      position: Position(latitude: -6.2149, longitude: 106.8707),
      city: "Jakarta Timur"
    ),
    Station(
      code: "CKR",
      name: "Cikampek",
      position: Position(latitude: -6.4197, longitude: 107.4561),
      city: "Karawang"
    ),
    Station(
      code: "BD",
      name: "Bandung",
      position: Position(latitude: -6.9147, longitude: 107.6098),
      city: "Bandung"
    ),
  ]

  let segments = [
    JourneySegment(
      fromStationId: "GMR",
      toStationId: "JNG",
      departure: Date().addingTimeInterval(-3600),
      arrival: Date().addingTimeInterval(-1800),
      routeId: "r1"
    ),
    JourneySegment(
      fromStationId: "JNG",
      toStationId: "CKR",
      departure: Date().addingTimeInterval(-1680),
      arrival: Date().addingTimeInterval(300),
      routeId: "r2"
    ),
    JourneySegment(
      fromStationId: "CKR",
      toStationId: "BD",
      departure: Date().addingTimeInterval(420),
      arrival: Date().addingTimeInterval(3600),
      routeId: "r3"
    ),
  ]

  let journeyData = TrainJourneyData(
    trainId: "T1",
    segments: segments,
    allStations: stations,
    userSelectedFromStation: stations[0],
    userSelectedToStation: stations[3],
    userSelectedDepartureTime: Date().addingTimeInterval(-3600),
    userSelectedArrivalTime: Date().addingTimeInterval(3600),
    selectedDate: Date()
  )

  let train = ProjectedTrain(
    id: "T1-0",
    code: "T1",
    name: "Argo Parahyangan",
    position: Position(latitude: -6.2149, longitude: 106.8707),
    moving: true,
    bearing: 45,
    routeIdentifier: "r2",
    speedKph: 80,
    fromStation: stations[1],
    toStation: stations[2],
    segmentDeparture: Date().addingTimeInterval(-1680),
    segmentArrival: Date().addingTimeInterval(300),
    progress: 0.6,
    journeyDeparture: Date().addingTimeInterval(-3600),
    journeyArrival: Date().addingTimeInterval(3600)
  )

  JourneyProgressView(
    train: train,
    journeyData: journeyData,
    selectedDate: Date(),
    onDelete: {}
  )
}
