import ConvexMobile
import Foundation
import OSLog
import SwiftUI

extension EnvironmentValues {
  @Entry var convexClient = Dependencies.shared.convexClient
  @Entry var selectedStation: Station? = nil
}
