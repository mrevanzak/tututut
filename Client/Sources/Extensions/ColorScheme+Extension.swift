//
//  ColorScheme+Extension.swift
//  kreta
//
//  Created by Gilang Banyu Biru Erassunu on 17/11/25.
//

import Foundation
import SwiftUI

extension ColorScheme {
  var keretaName: String {
    switch self {
    case .dark:
      return "keretaDark"
    default:
      return "keretaLight"
    }
  }
  
  var notYetDepart: String {
    switch self {
    case .dark:
      return "NotYetDepartDark"
    default:
      return "NotYetDepartLight"
    }
  }
  
  var keretaBackground: String {
    switch self {
    case .dark:
      return "keretaLowerBackgroundDark"
    default:
      return "keretaLowerBackgroundLight"
    }
  }
}
