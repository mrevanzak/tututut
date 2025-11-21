//
//  MapStylePicker.swift
//  kreta
//
//  Map overlay style selection component with iOS 26 liquid glass effect
//

import SwiftUI

enum MapStyleOption: String, CaseIterable {
  case standard = "Standard"
  case hybrid = "Hybrid"

  var icon: String {
    switch self {
    case .standard:
      return "map"
    case .hybrid:
      return "globe.asia.australia.fill"
    }
  }

  var displayName: String {
    return rawValue
  }
}

struct MapControl: View {
  @Environment(TrainMapStore.self) private var trainMapStore
  @Environment(Router.self) private var router
  @Environment(\.colorScheme) private var colorScheme

  @Binding var isFollowing: Bool
  @Binding var focusTrigger: Bool
  @Binding var userHasPanned: Bool
  
  // New parameter to determine what focus button should do
  let isTrackingTrain: Bool

  @Namespace private var namespace

  var body: some View {
    GlassEffectContainer(spacing: 8) {
      VStack(alignment: .trailing, spacing: 8) {
        mapStylePicker()
        
        Button {
          router.navigate(to: .sheet(.searchByStation))
        } label: {
          buttonLabel(icon: "magnifyingglass", tooltip: "Search by Station")
        }

        if showFocusButton {
          Button {
            focusTrigger = true
          } label: {
            buttonLabel(icon: focusButtonIcon, tooltip: focusButtonTooltip)
          }
        }
      }
    }
    .animation(.default, value: showFocusButton)
    .padding(.trailing)
    .padding(.top, Screen.safeArea.top)
    .ignoresSafeArea(edges: .top)
    .id(colorScheme) // Force view recreation on color scheme change
  }

  private var showFocusButton: Bool {
    return userHasPanned
  }
  
  // Dynamic icon based on what we're tracking
  private var focusButtonIcon: String {
    if isTrackingTrain {
      return "scope" // Train tracking icon
    } else {
      return "location.fill" // User location icon
    }
  }
  
  // Dynamic tooltip for accessibility
  private var focusButtonTooltip: String {
    if isTrackingTrain {
      return "Focus on Train"
    } else {
      return "Focus on My Location"
    }
  }

  func mapStylePicker() -> some View {
    Menu {
      Picker(
        selection: Binding(
          get: { trainMapStore.selectedMapStyle }, set: { trainMapStore.selectedMapStyle = $0 })
      ) {
        ForEach(MapStyleOption.allCases, id: \.self) { style in
          Label(style.displayName, systemImage: style.icon)
            .tag(style)
        }
      } label: {
        EmptyView()
      }
      .pickerStyle(.inline)
    } label: {
      buttonLabel(icon: trainMapStore.selectedMapStyle.icon, tooltip: "Select Map Style")
    }
    .accessibilityLabel("Select Map Style")
  }

  func buttonLabel(icon: String, tooltip: String? = nil) -> some View {
    Image(systemName: icon)
      .font(.headline)
      .frame(width: 44, height: 44)
      .glassEffect(.regular.interactive())
      .glassEffectID(icon, in: namespace)
      .accessibilityLabel(tooltip ?? icon)
  }
}

#Preview {
  MapControl(
    isFollowing: .constant(true),
    focusTrigger: .constant(false),
    userHasPanned: .constant(false),
    isTrackingTrain: false
  )
  .environment(Router.previewRouter())
  .environment(TrainMapStore.preview)
  .padding()
}
