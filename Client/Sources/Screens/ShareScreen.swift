import SwiftUI
import MapKit

fileprivate let kInstagramAppId = "793250190549271"

struct ShareScreen: View {
    @Environment(TrainMapStore.self) private var mapStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    // Instagram URL
    let instagramURL = URL(string: "instagram-stories://share?source_application=\(kInstagramAppId)")!

    // --- Captured / static state (snapshotted once) ---
    @State private var capturedTrain: ProjectedTrain?
    @State private var capturedRoutes: [Route] = []
    @State private var capturedFrom: Station?
    @State private var capturedTo: Station?
    @State private var capturedMapImage: UIImage? = nil
    @State private var isCapturing: Bool = false
    @State private var captureError: String? = nil
    @State private var showShareConfirmation: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if mapStore.selectedTrain != nil {
                    Text("Story Preview")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Group {
                        if let bg = capturedMapImage {
                            JourneyStoryStaticView(
                                backgroundImage: bg,
                                trainName: capturedTrain?.name ?? "My Journey",
                                fromName: capturedFrom?.name,
                                toName: capturedTo?.name,
                                isForSharing: false  // ← Preview mode
                            )
                            .frame(width: 270, height: 480) // preview size only
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        } else {
                            // placeholder while capturing
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.secondary.opacity(0.15))
                                .frame(width: 270, height: 480)
                                .overlay {
                                    if isCapturing {
                                        ProgressView("Capturing…")
                                    } else {
                                        Text("Tap Capture to snapshot journey")
                                            .font(.subheadline)
                                            .multilineTextAlignment(.center)
                                            .padding()
                                    }
                                }
                        }
                    }

                    HStack {
//                        Button {
//                            Task { await captureStaticSnapshot(scale: displayScale) }
//                        } label: {
//                            Text("Capture")
//                                .frame(maxWidth: .infinity)
//                                .padding()
//                                .background(Color.gray.opacity(0.15))
//                                .cornerRadius(10)
//                        }

                        if UIApplication.shared.canOpenURL(instagramURL) {
                            Button(action: { showShareConfirmation = true }) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            colors: [Color.purple, Color.red, Color.orange],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .disabled(capturedMapImage == nil)
                        } else {
                            Button {
                                // fallback: open app store link
                                if let url = URL(string: "https://apps.apple.com/app/instagram/id389801252") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Text("Install Instagram")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                        }
                    }

                    if let err = captureError {
                        Text(err)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }

                } else {
                    ContentUnavailableView(
                        "No Journey Selected",
                        systemImage: "train.side.front.car",
                        description: Text("Please select a train journey on the map to share.")
                    )
                }
            }
            .padding()
            .navigationTitle("Share Journey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: { dismiss() })
                }
            }
            .onAppear {
                // auto-capture once when view appears
                Task { await captureStaticSnapshot(scale: displayScale) }
            }
            .alert("Share to Instagram?", isPresented: $showShareConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Open Instagram") {
                    shareToInstagram()
                }
            } message: {
                Text("This will open Instagram and prepare your journey story. You may see a paste permission notification from Instagram.")
            }
        }
    }

    // MARK: - Capture static snapshot
    @MainActor
    private func captureStaticSnapshot(scale: CGFloat) async {
        guard let journey = mapStore.selectedJourneyData else {
            captureError = "No journey data available"
            return
        }

        isCapturing = true
        captureError = nil

        // freeze the model data (take copies)
        let train = mapStore.liveTrainPosition ?? mapStore.selectedTrain
        let routes = filteredRoutes
        let from = fromStation
        let to = toStation

        // prepare coords for region
        var coords: [CLLocationCoordinate2D] = []
        if let from = from { coords.append(from.coordinate) }
        if let to = to { coords.append(to.coordinate) }
        if let t = train { coords.append(t.coordinate) }

        // compute region using local helper
        let region = regionForCoordinates(coords)

        // create snapshot options
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.scale = scale
        options.size = CGSize(width: 1080, height: 1920) // full-screen story ratio (9:16)
        // Replace previous mapType and POI settings with preferredConfiguration
        let config = MKStandardMapConfiguration()
        config.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = config

        let snapshotter = MKMapSnapshotter(options: options)

        do {
            let snap = try await snapshotter.start()

            // Draw overlays (routes + annotations) on top of snapshot.image
            let renderer = UIGraphicsImageRenderer(size: options.size)
            let finalImg = renderer.image { ctx in
                // draw base map
                snap.image.draw(at: CGPoint.zero)

                // convert coordinates to points via snapshot
                func point(for coord: CLLocationCoordinate2D) -> CGPoint {
                    let p = snap.point(for: coord)
                    // MKMapSnapshotter's points are already in image coordinate space
                    return p
                }

                // draw routes (if any)
                ctx.cgContext.setLineWidth(8.0)
                ctx.cgContext.setLineCap(.round)
                ctx.cgContext.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.9).cgColor)

                for route in routes {
                    let pts = route.coordinates.map { point(for: $0) }
                    guard pts.count > 1 else { continue }
                    ctx.cgContext.beginPath()
                    ctx.cgContext.move(to: pts[0])
                    for p in pts.dropFirst() { ctx.cgContext.addLine(to: p) }
                    ctx.cgContext.strokePath()
                }

                // draw start marker
                if let from = from {
                    let p = point(for: from.coordinate)
                    drawStationMarker(ctx: ctx.cgContext, at: p, color: .systemGreen, code: from.code)
                }
                // draw end marker
                if let to = to {
                    let p = point(for: to.coordinate)
                    drawStationMarker(ctx: ctx.cgContext, at: p, color: .systemRed, code: to.code)
                }
                // draw train marker
                if let t = train {
                    let p = point(for: t.coordinate)
                    drawTrainMarker(ctx: ctx.cgContext, at: p)
                }
            }

            // set captured state
            self.capturedTrain = train
            self.capturedRoutes = routes
            self.capturedFrom = from
            self.capturedTo = to
            self.capturedMapImage = finalImg
        } catch {
            captureError = "Snapshot failed: \(error.localizedDescription)"
            print("Snapshot error:", error)
        }

        isCapturing = false
    }

    private func regionForCoordinates(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard coords.count > 1 else {
            return MKCoordinateRegion(center: coords.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                      span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
        }
        let minLat = coords.map { $0.latitude }.min() ?? 0
        let maxLat = coords.map { $0.latitude }.max() ?? 0
        let minLon = coords.map { $0.longitude }.min() ?? 0
        let maxLon = coords.map { $0.longitude }.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.4 + 0.04,
                                    longitudeDelta: (maxLon - minLon) * 1.2 + 0.04)
        return MKCoordinateRegion(center: center, span: span)
    }

    // helper drawing functions
    private func drawStationMarker(ctx: CGContext, at point: CGPoint, color: UIColor, code: String) {
        // circle
        let r: CGFloat = 18
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r*2, height: r*2))

        // code label background (rounded rect)
        let label = NSString(string: code)
        let font = UIFont.boldSystemFont(ofSize: 14)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let labelSize = label.size(withAttributes: attrs)
        let padding: CGFloat = 8
        let rect = CGRect(x: point.x - labelSize.width/2 - padding/2,
                          y: point.y - r - 6 - labelSize.height,
                          width: labelSize.width + padding,
                          height: labelSize.height + 4)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        ctx.setFillColor(UIColor.systemGray.withAlphaComponent(0.8).cgColor)
        ctx.addPath(path.cgPath)
        ctx.fillPath()

        // draw text
        label.draw(in: CGRect(x: rect.minX + padding/4, y: rect.minY + 2, width: labelSize.width, height: labelSize.height), withAttributes: attrs)
    }

    private func drawTrainMarker(ctx: CGContext, at point: CGPoint) {
        // simple tram icon circle
        let r: CGFloat = 14
        ctx.setFillColor(UIColor.systemYellow.cgColor)
        ctx.fillEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r*2, height: r*2))

        // small inner white circle
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
    }

    // MARK: - Share to Instagram (render at FULL RESOLUTION)
    @MainActor
    private func shareToInstagram() {
        guard let bg = capturedMapImage else {
            print("No captured image to share")
            return
        }

        // Build the static view with isForSharing = true
        let staticView = JourneyStoryStaticView(
            backgroundImage: bg,
            trainName: capturedTrain?.name ?? "My Journey",
            fromName: capturedFrom?.name,
            toName: capturedTo?.name,
            isForSharing: true  // ← Sharing mode (4x scale)
        )
        
        // Render at FULL resolution
        let renderer = ImageRenderer(content: staticView)
        renderer.scale = displayScale
        // No need for proposedSize - the view handles its own size now

        guard let uiImage = renderer.uiImage,
              let imageData = uiImage.pngData()
        else {
            print("Error: Could not render final image")
            return
        }

        openInInstagram(imageData: imageData)
    }

    private func openInInstagram(imageData: Data) {
        let pasteboardItems = [
            "com.instagram.sharedSticker.backgroundImage": imageData
        ]
        UIPasteboard.general.setItems([pasteboardItems], options: [
            .expirationDate: Date().addingTimeInterval(60 * 5)
        ])
        guard UIApplication.shared.canOpenURL(instagramURL) else {
            print("Instagram not available")
            return
        }
        UIApplication.shared.open(instagramURL) { success in
            print(success ? "Opened IG" : "Failed to open IG")
        }
    }

    // MARK: Helpers (same filtering logic)
    private var fromStation: Station? {
        guard let journey = mapStore.selectedJourneyData,
              let firstStopId = journey.stopStationIds(dwellThreshold: 0).first else { return nil }
        return mapStore.stations.first { $0.id == firstStopId || $0.code == firstStopId }
    }

    private var toStation: Station? {
        guard let journey = mapStore.selectedJourneyData else { return nil }
        let toStationCode = journey.userSelectedToStation.code
        return mapStore.stations.first { $0.code == toStationCode }
    }

    private var filteredRoutes: [Route] {
        guard let journeyData = mapStore.selectedJourneyData else { return [] }
        var routeIds = Set<String>()
        for segment in journeyData.segments {
            if let routeId = segment.routeId {
                routeIds.insert(routeId)
            }
        }
        return mapStore.routes.filter { routeIds.contains($0.id) }
    }
}

