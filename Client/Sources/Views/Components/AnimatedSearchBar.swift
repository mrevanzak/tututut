//
//  AnimatedSearchBar.swift
//  tututut
//
//  Created by Gilang Banyu Biru Erassunu on 24/10/25.
//

import SwiftUI

struct AnimatedSearchBar: View {
  let step: SelectionStep
  let departureStation: Station?
  let arrivalStation: Station?
  let selectedDate: Date?
  @Binding var searchText: String
  let onDepartureChipTap: () -> Void
  let onArrivalChipTap: () -> Void
  let onDateChipTap: (() -> Void)?
  let onDateTextSubmit: (() -> Void)?

  @Namespace private var animation
  @State private var clearingDeparture = false
  @State private var clearingArrival = false

  var body: some View {
    HStack(alignment: .center, spacing: 4) {
      // Departure station chip (visible from arrival step onwards, unless clearing)
      if let departure = departureStation, step != .departure && !clearingDeparture {
        Button {
          clearingDeparture = true
          Task {
            try? await Task.sleep(for: .milliseconds(50))
            onDepartureChipTap()
            try? await Task.sleep(for: .milliseconds(50))
            clearingDeparture = false
          }
        } label: {
          stationChip(departure, id: "departure", isClearing: clearingDeparture)
        }
        .buttonStyle(ChipButtonStyle())
        .transition(
          .asymmetric(
            insertion: .scale(scale: 0.8)
              .combined(with: .opacity)
              .combined(with: .offset(x: -20)),
            removal: .scale(scale: 0.8).combined(with: .opacity)
          )
        )
        .sensoryFeedback(.selection, trigger: clearingDeparture)
      }

      // Arrow (visible when departure is selected and not in departure step)
      if departureStation != nil && step != .departure {
        Image(systemName: "arrow.right")
          .font(.caption)
          .fontWeight(.bold)
          .foregroundStyle(.textSecondary)
          .transition(.scale(scale: 0.5).combined(with: .opacity))
      }

      // Arrival station chip (visible from date step onwards, unless clearing)
      if let arrival = arrivalStation, (step == .date || step == .results) && !clearingArrival {
        Button {
          clearingArrival = true
          Task {
            try? await Task.sleep(for: .milliseconds(50))
            onArrivalChipTap()
            try? await Task.sleep(for: .milliseconds(50))
            clearingArrival = false
          }
        } label: {
          stationChip(arrival, id: "arrival", isClearing: clearingArrival)
        }
        .buttonStyle(ChipButtonStyle())
        .transition(
          .asymmetric(
            insertion: .scale(scale: 0.8)
              .combined(with: .opacity)
              .combined(with: .offset(x: -20)),
            removal: .scale(scale: 0.8).combined(with: .opacity)
          )
        )
        .sensoryFeedback(.selection, trigger: clearingArrival)
      }

      // Text field for station selection (departure or arrival)
      if step == .departure || step == .arrival {
        searchTextField
          .transition(
            .asymmetric(
              insertion: .scale(scale: 0.95)
                .combined(with: .opacity)
                .combined(with: .offset(x: 20)),
              removal: .scale(scale: 0.95)
                .combined(with: .opacity)
                .combined(with: .offset(x: -20))
            ))
      }

      // Date text field (only visible in date step when no date is selected yet)
      if step == .date && selectedDate == nil {
        dateTextField
          .transition(
            .asymmetric(
              insertion: .scale(scale: 0.95)
                .combined(with: .opacity)
                .combined(with: .offset(x: 20)),
              removal: .scale(scale: 0.95)
                .combined(with: .opacity)
                .combined(with: .offset(x: -20))
            ))
      }

      // Date chip (visible in date and results steps when date is selected)
      if step == .date || step == .results, let date = selectedDate {
        Button {
          onDateChipTap?()
        } label: {
          dateChip(date)
        }
        .buttonStyle(ChipButtonStyle())
        .transition(
          .asymmetric(
            insertion: .scale(scale: 0.8)
              .combined(with: .opacity)
              .combined(with: .offset(x: 20)),
            removal: .scale(scale: 0.8).combined(with: .opacity)
          ))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: step)
    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: departureStation?.id)
    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: arrivalStation?.id)
    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: selectedDate)
  }

  private var searchTextField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.subheadline)
        .foregroundStyle(.tertiary)

      TextField("Stasiun / Kota", text: $searchText)
        .textFieldStyle(.plain)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 10)
    .glassEffect()
    .frame(maxWidth: .infinity)
  }

  private var dateTextField: some View {
    HStack(spacing: 8) {
      TextField("Bulan, Tanggal", text: $searchText)
        .textFieldStyle(.plain)
        .keyboardType(.numbersAndPunctuation)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .submitLabel(.done)
        .onSubmit {
          onDateTextSubmit?()
        }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 10)
    .glassEffect()
    .frame(maxWidth: .infinity)
  }

  private func stationChip(_ station: Station, id: String, isClearing: Bool) -> some View {
    HStack {
      Text(station.code)
        .font(.callout)
        .foregroundStyle(.sublime)
        .opacity(isClearing ? 0 : 1)
        .scaleEffect(isClearing ? 0.5 : 1)
    }
    .frame(minWidth: 44)
    .padding(.horizontal, 8)
    .padding(.vertical, 10)
    .glassEffect()
    .matchedGeometryEffect(id: id, in: animation)
    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .hoverEffect(.highlight)
    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isClearing)
  }

  private func dateChip(_ date: Date) -> some View {
    HStack(spacing: 4) {
      Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
        .font(.callout)
        .foregroundStyle(.sublime)
        .lineLimit(1)
        .minimumScaleFactor(1)
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.horizontal, 8)
    .padding(.vertical, 10)
    .glassEffect()
  }
}

// MARK: - Button Style

/// Custom button style for station chips with press animation and feedback.
struct ChipButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
      .opacity(configuration.isPressed ? 0.8 : 1.0)
      .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
  }
}
