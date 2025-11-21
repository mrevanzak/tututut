//
//  StationExplorerContainer.swift
//  kreta
//
//  Unified container for station search and schedule viewing
//  Manages smooth transitions between search and schedule modes
//

import MapKit
import SwiftUI

struct StationExplorerContainer: View {
  @Environment(TrainMapStore.self) private var mapStore
  @Environment(\.dismiss) private var dismiss
  
  @State private var showingSchedule: Bool = false
  @State private var selectedDetent: PresentationDetent = .large
  @State private var mode: StationExplorerMode = .search
  @State private var allowedDetents: Set<PresentationDetent> = [.large]
  
  private var backCallback: (() -> Void)? {
    if mode == .search {
      return handleBackToSearch
    }
    return nil
  }
  
  var body: some View {
    ZStack {
      if !showingSchedule {
        SearchByStationView(onStationSelected: handleStationSelected)
          .padding(.top)
//          .transition(.move(edge: .top))
      }
      
      if showingSchedule, let station = mapStore.selectedStationForSchedule {
        StationScheduleView(mode: mode, onBack: backCallback)
//          .transition(.move(edge: .bottom))
          .id(station.id)
      }
    }
    .animation(.easeInOut(duration: 0.3), value: showingSchedule)
    .presentationDetents(allowedDetents, selection: $selectedDetent)
    .presentationDragIndicator(.visible)
    .presentationBackgroundInteraction(.enabled)
    .interactiveDismissDisabled(showingSchedule && mode == .search)
    .onDisappear {
      // Reset state when sheet is dismissed
      if mode == .direct {
        // User dismissed from direct mode, clear the selected station
        mapStore.selectedStationForSchedule = nil
      }
      // Reset to initial state
      showingSchedule = false
      mode = .search
      allowedDetents = [.large]
      selectedDetent = .large
    }
    .onAppear {
      // If a station is already selected when opening, show schedule directly in direct mode
      if mapStore.selectedStationForSchedule != nil {
        mode = .direct
        showingSchedule = true
        selectedDetent = .large
        allowedDetents = [.large]
      } else {
        mode = .search
        selectedDetent = .large
        allowedDetents = [.large]
      }
    }
    .onChange(of: mapStore.selectedStationForSchedule) { _, newStation in
      // When station changes (from map marker tap)
      if newStation != nil {
        if showingSchedule {
          // Already showing schedule, station changed from map marker
          // Keep current mode and detents, just reload content (handled by .id modifier)
        } else {
          // Transition from search to schedule
          handleStationSelected(newStation!)
        }
      }
    }
  }
  
  private func handleStationSelected(_ station: Station) {
    // Set the selected station in the store
    mapStore.selectedStationForSchedule = station
    
    // Focus the map camera on the selected station
    focusMapOnStation(station)
    
    // Switch to search mode with resizable detents
    mode = .search
    allowedDetents = [.fraction(0.45), .large]
    
    // Change to quarter-height detent and switch to schedule view
    withAnimation(.easeInOut(duration: 0.3)) {
      selectedDetent = .fraction(0.45)
      showingSchedule = true
    }
  }
  
  private func handleBackToSearch() {
    // Clear selected station and return to search
    mapStore.selectedStationForSchedule = nil
    
    mode = .search
    allowedDetents = [.large]
    
    withAnimation(.easeInOut(duration: 0.3)) {
      selectedDetent = .large
      showingSchedule = false
    }
  }
  
  private func focusMapOnStation(_ station: Station) {
    // Post notification to focus map camera
    NotificationCenter.default.post(
      name: NSNotification.Name("FocusOnStation"),
      object: nil,
      userInfo: ["station": station]
    )
  }
}

// Backward compatibility alias
typealias SearchByStationContainer = StationExplorerContainer

#Preview {
  StationExplorerContainer()
    .environment(TrainMapStore.preview)
}
