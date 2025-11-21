//
//  SearchByStationContainer.swift
//  kreta
//
//  Container view that manages transition between SearchByStationView and StationScheduleView
//

import MapKit
import SwiftUI

struct SearchByStationContainer: View {
  @Environment(TrainMapStore.self) private var mapStore
  @Environment(\.dismiss) private var dismiss
  
  @State private var showingSchedule: Bool = false
  @State private var selectedDetent: PresentationDetent = .large
  
  var body: some View {
    Group {
      if showingSchedule {
        StationScheduleView()
          .transition(.move(edge: .trailing))
      } else {
        SearchByStationView(onStationSelected: handleStationSelected)
          .padding(.top)
          .transition(.move(edge: .leading))
      }
    }
    .animation(.easeInOut(duration: 0.3), value: showingSchedule)
    .presentationDetents([selectedDetent], selection: $selectedDetent)
    .presentationDragIndicator(.visible)
//    .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.25)))
  }
  
  private func handleStationSelected(_ station: Station) {
    // Set the selected station in the store
    mapStore.selectedStationForSchedule = station
    
    // Focus the map camera on the selected station
    focusMapOnStation(station)
    
    // Change to quarter-height detent and switch to schedule view
    withAnimation(.easeInOut(duration: 0.3)) {
      selectedDetent = .fraction(0.45)
      showingSchedule = true
    }
  }
  
  private func focusMapOnStation(_ station: Station) {
    // Post a notification or use a binding to focus the map
    // Since TrainMapView uses mapStore, we can trigger a focus through the store
    // We'll need to add a published property to TrainMapStore for this
    
    // For now, we can set a flag that TrainMapView can observe
    NotificationCenter.default.post(
      name: NSNotification.Name("FocusOnStation"),
      object: nil,
      userInfo: ["station": station]
    )
  }
}

#Preview {
  SearchByStationContainer()
    .environment(TrainMapStore.preview)
}
