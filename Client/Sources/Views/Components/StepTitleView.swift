//
//  StepTitleView.swift
//  kreta
//
//  Created by Gilang Banyu Biru Erassunu on 22/10/25.
//

import SwiftUI

/// A text view that dynamically animates only the changing part of the text.
/// Automatically detects common prefix and only animates the differing suffix.
struct StepTitleView: View {
  let text: String
  let showCalendar: Bool

  @State private var previousText: String = ""
  @State private var commonPrefix: String = ""

  var body: some View {
    if showCalendar {
      calendarTitleView
    } else {
      stepTitleView
    }
  }

  // MARK: - Private Views

  private var calendarTitleView: some View {
    Text(text)
      .id(text)
      .transition(
        .asymmetric(
          insertion: .offset(y: -10).combined(with: .opacity),
          removal: .offset(y: 10).combined(with: .opacity)
        )
      )
      .animation(.spring(response: 0.35, dampingFraction: 0.85), value: text)
  }

  private var stepTitleView: some View {
    HStack(spacing: 0) {
      Text(staticPart)

      ZStack(alignment: .leading) {
        // Invisible placeholder to maintain layout stability
        Text(dynamicPart)
          .opacity(0)

        // Visible animated text with contentTransition
        Text(dynamicPart)
          .id(dynamicPart)
          .contentTransition(.numericText())
          .transition(
            .asymmetric(
              insertion: .offset(y: -8).combined(with: .opacity),
              removal: .offset(y: 8).combined(with: .opacity)
            )
          )
      }
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: dynamicPart)
    .onAppear {
      initializeText()
    }
    .onChange(of: text) { oldValue, newValue in
      updateCommonPrefix(oldValue: oldValue, newValue: newValue)
    }
  }

  // MARK: - Computed Properties

  private var staticPart: String {
    commonPrefix.isEmpty ? "" : commonPrefix
  }

  private var dynamicPart: String {
    guard !text.isEmpty else { return "" }
    guard !commonPrefix.isEmpty else { return text }
    guard text.hasPrefix(commonPrefix) else { return text }
    return String(text.dropFirst(commonPrefix.count))
  }

  // MARK: - Private Methods

  private func initializeText() {
    previousText = text
    commonPrefix = text
  }

  private func updateCommonPrefix(oldValue: String, newValue: String) {
    if !oldValue.isEmpty && !newValue.isEmpty {
      commonPrefix = longestCommonPrefix(oldValue, newValue)
    } else {
      commonPrefix = ""
    }
    previousText = newValue
  }

  /// Computes the longest common prefix between two strings.
  private func longestCommonPrefix(_ str1: String, _ str2: String) -> String {
    guard !str1.isEmpty && !str2.isEmpty else { return "" }

    let chars1 = Array(str1)
    let chars2 = Array(str2)
    let minLength = min(chars1.count, chars2.count)

    var commonLength = 0
    for i in 0..<minLength {
      if chars1[i] == chars2[i] {
        commonLength += 1
      } else {
        break
      }
    }

    return String(chars1.prefix(commonLength))
  }
}
