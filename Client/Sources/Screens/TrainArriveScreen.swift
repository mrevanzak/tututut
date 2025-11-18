import Foundation
import OSLog
import StoreKit
import SwiftUI

struct PulsatingArcShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    // The SVG is for width:393, height:572
    // We'll scale accordingly to fit rect
    let scaleX = rect.width / 393.0
    let scaleY = rect.height / 572.0
    path.move(to: CGPoint(x: 355.709 * scaleX, y: 526.094 * scaleY))
    path.addCurve(
      to: CGPoint(x: 37.2905 * scaleX, y: 526.093 * scaleY),
      control1: CGPoint(x: 258.063 * scaleX, y: 586.142 * scaleY),
      control2: CGPoint(x: 134.937 * scaleX, y: 586.142 * scaleY))
    path.addLine(to: CGPoint(x: -111.525 * scaleX, y: 434.579 * scaleY))
    path.addCurve(
      to: CGPoint(x: 47.6843 * scaleX, y: -128.25 * scaleY),
      control1: CGPoint(x: -372.618 * scaleX, y: 274.018 * scaleY),
      control2: CGPoint(x: -258.828 * scaleX, y: -128.25 * scaleY))
    path.addLine(to: CGPoint(x: 345.316 * scaleX, y: -128.25 * scaleY))
    path.addCurve(
      to: CGPoint(x: 504.525 * scaleX, y: 434.578 * scaleY),
      control1: CGPoint(x: 651.828 * scaleX, y: -128.25 * scaleY),
      control2: CGPoint(x: 765.619 * scaleX, y: 274.018 * scaleY))
    path.addLine(to: CGPoint(x: 355.709 * scaleX, y: 526.094 * scaleY))
    path.closeSubpath()
    return path
  }
}

struct TrainArriveScreen: View {
  let stationCode: String
  let stationName: String

  @Environment(\.dismiss) var dismiss
  @Environment(\.requestReview) private var requestReview
  @Environment(TrainMapStore.self) private var trainMapStore

  @State private var pulse: Bool = false

  var body: some View {
    ZStack {
      // Vibrant green background
      Color(red: 0.647, green: 0.871, blue: 0.161)  // Approximate neon green
        .ignoresSafeArea()

      PulsatingArcShape()
        .fill(Color(red: 0.863, green: 1.0, blue: 0.541).opacity(0.5))
        .frame(width: 393, height: 470)
        .scaleEffect(pulse ? 1.07 : 0.97)
        .opacity(pulse ? 0.65 : 0.35)
        .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: pulse)
        .offset(y: -80)

      VStack(spacing: 0) {
        Spacer()

        // App icon and label
        HStack(spacing: 8) {
          Image(systemName: "tram.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
            .foregroundColor(.black)
          Text("kreta")
            .font(.title2.bold())
            .foregroundColor(.black)
        }

        Spacer().frame(height: 20)

        // Headline
        Text("Tiba di Stasiun")
          .font(.system(size: 42, weight: .bold))
          .foregroundColor(.black)
          .multilineTextAlignment(.center)

        Spacer().frame(height: 16)

        // Pin + Station
        VStack(spacing: 6) {
          Image("customPin")
            .resizable()
            .scaledToFit()
            .frame(width: 36, height: 36)
            .foregroundColor(.red)
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
          Text(stationCode)
            .font(.title2.bold())
            .foregroundColor(.black)
          Text(stationName)
            .font(.title3)
            .foregroundColor(.black.opacity(0.8))
        }

        Spacer()

        // 'Sip!' Button
        Button {
          AnalyticsEventService.shared.trackArrivalConfirmed(
            stationCode: stationCode, stationName: stationName)
          AnalyticsEventService.shared.trackJourneyCompletedMinimal(
            destinationCode: stationCode, destinationName: stationName,
            completionType: "arrival_screen")

          // Save completed journey to CloudKit in background
          if let train = trainMapStore.selectedTrain,
            let journeyData = trainMapStore.selectedJourneyData
          {
            Task.detached(priority: .background) {
              do {
                let now = Date()
                let completedJourney = JourneyHistoryService.buildCompletedJourney(
                  from: train,
                  journeyData: journeyData,
                  actualArrivalTime: now,
                  completionType: "arrival_screen",
                  wasTrackedUntilArrival: true
                )
                try await JourneyHistoryService.shared.saveCompletedJourney(completedJourney)
              } catch {
                // Log error but don't block UI - CloudKit operations are best-effort
                Logger(subsystem: "kreta", category: "TrainArriveScreen").warning(
                  "Failed to save journey to CloudKit: \(error.localizedDescription, privacy: .public)"
                )
              }
            }
          }

          Task { @MainActor in
            dismiss()
            await trainMapStore.clearSelectedTrain()
            try? await Task.sleep(for: .seconds(1))
            requestReview()
          }
        } label: {
          Text("Sip!")
            .font(.system(size: 28, weight: .semibold))
            .foregroundColor(Color(red: 0.914, green: 1.0, blue: 0.698))
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(Color.black)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
      }
    }
    .onAppear {
      pulse = true
      Dependencies.shared.telemetry.screen(
        name: "TrainArriveScreen",
        properties: [
          "station_code": stationCode,
          "station_name": stationName,
        ]
      )
    }
  }
}

#Preview {
  TrainArriveScreen(stationCode: "SLO", stationName: "Solo Balapan")
}
