import MapKit
import SwiftUI

struct RailPassMapView: View {
  let routes: [Route]
  let stations: [Station]  // To show markers if needed

  var body: some View {
    Map {
      // Draw all routes
      ForEach(routes) { route in
        MapPolyline(coordinates: route.coordinates)
          .stroke(Color.blue.opacity(0.6), lineWidth: 2)
      }

      // Draw visited stations (optional, maybe just dots)
      ForEach(stations) { station in
        Annotation(station.code, coordinate: station.coordinate) {
          Circle()
            .fill(Color.white)
            .frame(width: 6, height: 6)
            .overlay(
              Circle()
                .stroke(Color.blue, lineWidth: 2)
            )
        }
      }
    }
    .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
    .mapControlVisibility(.hidden)  // Clean look
    .disabled(true)  // Static map for aesthetics? Or interactive? Flighty is interactive.
    // Let's keep it interactive but minimal
  }
}
