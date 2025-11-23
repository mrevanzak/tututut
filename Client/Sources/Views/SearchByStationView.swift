//
//  SearchByStationView.swift
//  kreta
//
//  Created by Gilang Banyu Biru Erassunu on 21/11/25.
//

import SwiftUI

struct SearchByStationView: View {
  @Environment(TrainMapStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  
  let onStationSelected: (Station) -> Void
  
  @State private var searchText: String = ""
  
  private var filteredStations: [Station] {
    let stations = searchText.isEmpty 
      ? store.stations 
      : store.stations.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    
    // Sort with nearest stations first, then alphabetically
    let proximityService = StationProximityService.shared
    let nearest = stations.filter { proximityService.isNearestStation($0) }
    let others = stations.filter { !proximityService.isNearestStation($0) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    
    return nearest + others
  }
  
  var body: some View {
    ZStack(alignment: .topLeading) {
      if !store.stations.isEmpty {
        List(filteredStations) { station in
          let isNearest = StationProximityService.shared.isNearestStation(station)
          StationRow(station: station, isNearestStation: isNearest)
            .onTapGesture {
              onStationSelected(station)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .top) {
          Color.clear.frame(height: 92)
        }
        
      } else {
        emptyStateView
      }
      
      headerView
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .background(
          LinearGradient(
            colors: [
              Color.backgroundPrimary,
              Color.backgroundPrimary.opacity(0.9),
              Color.backgroundPrimary.opacity(0.9),
              Color.backgroundPrimary.opacity(0),
            ],
            startPoint: .top,
            endPoint: .bottom
          )
        )
    }
    
  }
  
  private var headerView: some View {
    VStack(spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Cari Stasiun")
            .font(.title2)
          Text("Cek jadwal kereta berdasarkan stasiun")
            .font(.subheadline)
            .foregroundStyle(.sublime)
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
        .foregroundStyle(.backgroundSecondary)
        .glassEffect(.regular.tint(.backgroundSecondary))
      }
      
      searchTextField
    }
  }
  
  private var searchTextField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.subheadline)
        .foregroundStyle(.tertiary)
      
      TextField("Cari Stasiun", text: $searchText)
        .textFieldStyle(.plain)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 10)
    .glassEffect()
    .frame(maxWidth: .infinity)
  }
  
  private var emptyStateView: some View {
    ContentUnavailableView(
      "Tidak Ada Stasiun",
      systemImage: "mappin.slash",
      description: Text("Ada Kesalahan")
    )
  }
}

#Preview {
  Group {
    SearchByStationView(onStationSelected: { _ in })
      .environment(TrainMapStore.preview)
  }
  .background(.backgroundPrimary)
}
