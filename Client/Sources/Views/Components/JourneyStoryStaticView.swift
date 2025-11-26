import SwiftUI

struct JourneyStoryStaticView: View {
    let backgroundImage: UIImage
    let trainName: String
    let fromName: String?
    let toName: String?
    let journeyDuration: String?
    let journeyDate: String?
    var isForSharing: Bool = false
    
    // Scale factor based on mode
    private var scaleFactor: CGFloat {
        isForSharing ? 4.0 : 1.0
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // full-screen background image
                Image(uiImage: backgroundImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                // gradient overlay for readability
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.3),
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.45)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Image("stamp")
                       .resizable()
                
                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 2 * scaleFactor) {
                        // Journey date - leading aligned
                        if let date = journeyDate {
                            HStack {
                                Text(date)
                                    .font(.system(size: 14 * scaleFactor, weight: .medium))
                                    .foregroundColor(.highlight)
                                Spacer()
                            }
                        }
                        
                        
                        // Train name and stations - center aligned
                        VStack(spacing: 8 * scaleFactor) {
                            // Stamp image
//                            Image("stamp")
                            
                            // Train name
                            Text(trainName)
                                .font(.system(size: 32 * scaleFactor, weight: .bold, design: .rounded))
                                .foregroundColor(.highlight)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .multilineTextAlignment(.center)
                            
                            // From and To stations
                            HStack(spacing: 16 * scaleFactor) {
                                Text(fromName ?? "BD")
                                    .font(.system(size: 32 * scaleFactor, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 32 * scaleFactor, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Text(toName ?? "SGU")
                                    .font(.system(size: 32 * scaleFactor, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Journey duration - trailing aligned
                        if let duration = journeyDuration {
                            HStack {
                                Spacer()
                                Text("Total Perjalanan: \(duration)")
                                    .font(.system(size: 8 * scaleFactor, weight: .medium))
                                    .foregroundColor(.highlight)
                            }
                        }
                    }
                    .frame(maxWidth: 240 * scaleFactor) // Consistent wrapper width
                    .padding(.horizontal, 28 * scaleFactor)
                    .padding(.bottom, 44 * scaleFactor)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .frame(width: 270 * scaleFactor, height: 480 * scaleFactor)
        .cornerRadius(20 * scaleFactor)
        .compositingGroup()
    }
}

#Preview("Journey Story Static View") {
    // Create a simple gradient-backed image for preview purposes
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 270, height: 480))
    let image = renderer.image { ctx in
        let bounds = CGRect(x: 0, y: 0, width: 270, height: 480)
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor.systemTeal.cgColor,
                UIColor.systemIndigo.cgColor
            ] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.cgContext.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.midX, y: bounds.minY),
            end: CGPoint(x: bounds.midX, y: bounds.maxY),
            options: []
        )

        // Add a subtle pattern so text contrast is visible
        UIColor.white.withAlphaComponent(0.08).setFill()
        for y in stride(from: 0, to: 480, by: 16) {
            ctx.cgContext.fill(CGRect(x: 0, y: y, width: 270, height: 1))
        }
    }

    return VStack(spacing: 24) {
        JourneyStoryStaticView(
            backgroundImage: image,
            trainName: "TURANGGA",
            fromName: "BD",
            toName: "SGU",
            journeyDuration: "8 jam 40 menit",
            journeyDate: "21 NOVEMBER 2025",
            isForSharing: false
        )
        .previewDisplayName("Normal")

        JourneyStoryStaticView(
            backgroundImage: image,
            trainName: "TURANGGA",
            fromName: "BD",
            toName: "SGU",
            journeyDuration: "8 jam 40 menit",
            journeyDate: "21 NOVEMBER 2025",
            isForSharing: true
        )
        .previewDisplayName("Sharing x4 scale")
    }
    .padding()
    .background(Color.black)
}
