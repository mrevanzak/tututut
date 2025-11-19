//
//  TrainResultsView.swift
//  kreta
//
//  Created by Gilang Banyu Biru Erassunu on 22/10/25.
//

import SwiftUI

struct TrainResultsView: View {
  let trains: [JourneyService.AvailableTrainItem]
  let uniqueTrainNames: [String]
  let selectedTrainNameFilter: String
  let isLoading: Bool
  let isTrainSelected: (JourneyService.AvailableTrainItem) -> Bool
  let onTrainTapped: (JourneyService.AvailableTrainItem) -> Void
  let onTrainSelected: () -> Void
  let onFilterChanged: (String) -> Void
  let selectedTrainItem: JourneyService.AvailableTrainItem?
  
  @Binding var isSearchBarOverContent: Bool
  
  var body: some View {
    ZStack {
      trainList
      
      TrainFilterPicker(
        selectedFilter: Binding(
          get: { selectedTrainNameFilter },
          set: { onFilterChanged($0) }
        ),
        uniqueTrainNames: uniqueTrainNames,
        isSearchBarOverContent: isSearchBarOverContent
      )
    }
    .safeAreaInset(edge: .bottom) {
      TrainTrackButton(
        isEnabled: selectedTrainItem != nil,
        onTap: onTrainSelected
      )
    }
  }
  
  // MARK: - Private Views
  
  private var trainList: some View {
    List {
      scrollOffsetDetector
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
      
      ForEach(trains) { item in
        let selected = isTrainSelected(item)
        
        TrainServiceRow(
          item: item
        )
        .contentShape(Rectangle())
        .onTapGesture {
          onTrainTapped(item)
        }
        .listRowBackground(
          selected ? Color.backgroundSecondary : Color.clear
        )
      }
    }
    .listStyle(.plain)
    .coordinateSpace(name: "listScroll")
    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
      isSearchBarOverContent = value < 14
    }
    .overlay {
      loadingOrEmptyState
    }
  }
  
  private var scrollOffsetDetector: some View {
    GeometryReader { geometry in
      Color.clear
        .preference(
          key: ScrollOffsetPreferenceKey.self,
          value: geometry.frame(in: .named("listScroll")).minY
        )
    }
    .frame(height: 0)
  }
  
  @ViewBuilder
  private var loadingOrEmptyState: some View {
    if isLoading {
      ProgressView()
        .controlSize(.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.backgroundPrimary)
    } else if trains.isEmpty {
      emptyStateView
    }
  }
  
  private var emptyStateView: some View {
    ContentUnavailableView(
      selectedTrainNameFilter == "Semua Kereta"
      ? "Tidak ada kereta tersedia" : "Tidak ditemukan",
      systemImage: "train.side.front.car",
      description: Text(
        selectedTrainNameFilter == "Semua Kereta"
        ? "Tidak ada layanan kereta untuk rute ini pada tanggal yang dipilih"
        : "Tidak ada kereta '\(selectedTrainNameFilter)' untuk rute ini"
      )
    )
  }
}

// MARK: - Train Filter Picker

private struct TrainFilterPicker: View {
  @Binding var selectedFilter: String
  let uniqueTrainNames: [String]
  let isSearchBarOverContent: Bool
  
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Spacer()
        
        customPickerLabel
        
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 20)
      
      Spacer()
    }
  }
  
  private var customPickerLabel: some View {
    ZStack {
      // Visual label
      HStack(spacing: 8) {
        Text(selectedFilter)
          .foregroundStyle(.primary)
        
        Image(systemName: "chevron.down")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .frame(alignment: .leading)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        .componentFill.opacity(isSearchBarOverContent ? 0.2 : 0.1),
        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
      )
      .glassEffect()
      .animation(.easeInOut(duration: 0.25), value: isSearchBarOverContent)
      
      // Invisible picker for interaction
      Picker("", selection: $selectedFilter) {
        ForEach(uniqueTrainNames, id: \.self) { trainName in
          Text(trainName).tag(trainName)
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .opacity(0.02)
      .contentShape(Rectangle())
    }
  }
  
}

// MARK: - Train Track Button

private struct TrainTrackButton: View {
  let isEnabled: Bool
  let onTap: () -> Void
  
  var body: some View {
    Button(action: onTap) {
      Text("Track Kereta")
        .font(.headline)
        .foregroundStyle(isEnabled ? .lessDark : .sublime)
        .frame(maxWidth: .infinity)
        .padding()
        .background(isEnabled ? .highlight : .inactiveButton)
        .cornerRadius(1000)
    }
    .buttonStyle(ScaleButtonStyle())
    .disabled(!isEnabled)
    .padding(.horizontal, 16)
    .padding(.top, 20)
    .padding(.bottom, 12)
    .background(Color.backgroundPrimary)
  }
}
