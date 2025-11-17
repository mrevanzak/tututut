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
  @Environment(\.colorScheme) private var colorScheme

  @Binding var isFollowing: Bool
  @Binding var focusTrigger: Bool
  @Binding var userHasPanned: Bool

  @Namespace private var namespace

  var body: some View {
    GlassEffectContainer(spacing: 8) {
      VStack(alignment: .trailing, spacing: 8) {
        mapStylePicker()

        if showFocusButton {
          Button {
            focusTrigger = true
          } label: {
            buttonLabel(icon: "scope")
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
      buttonLabel(icon: trainMapStore.selectedMapStyle.icon)
    }
    .accessibilityLabel("Select Map Style")
  }

  func buttonLabel(icon: String) -> some View {
    Image(systemName: icon)
      .font(.headline)
      .frame(width: 44, height: 44)
      .glassEffect(.regular.interactive())
      .glassEffectID(icon, in: namespace)
  }
}

#Preview {
  MapControl(isFollowing: .constant(true), focusTrigger: .constant(false), userHasPanned: .constant(false))
    .padding()
}
