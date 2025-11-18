//
//  ScrollOffsetPreferenceKey.swift
//  kreta
//
//  Created by Gilang Banyu Biru Erassunu on 22/10/25.
//

import SwiftUI

struct ScrollOffsetPreferenceKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
