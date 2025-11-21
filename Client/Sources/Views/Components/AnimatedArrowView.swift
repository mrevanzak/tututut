import SwiftUI

struct AnimatedArrowView: View {
  @State private var drawingProgress: CGFloat = 0.0
  @State private var arrowHeadScale: CGFloat = 0.0
  @State private var arrowHeadOpacity: Double = 0.0

  var color: Color = Color(hex: "8C8C8C")
  var lineWidth: CGFloat = 4.39505

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      let height = geometry.size.height

      // Calculate scale to fit within the frame while maintaining aspect ratio
      let scaleX = width / 56.0
      let scaleY = height / 60.0
      let scale = min(scaleX, scaleY)

      // Center the content
      let offsetX = (width - 56 * scale) / 2
      let offsetY = (height - 60 * scale) / 2

      ZStack {
        // Path 1: The Line (Stroke)
        ArrowLineShape()
          .trim(from: 0, to: drawingProgress)
          .stroke(
            color,
            style: StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round)
          )
          .offset(x: offsetX, y: offsetY)  // Offset the shape, not the path inside (since we handle scale in shape but not offset? Wait, let's handle transform in shape)

        // Path 2: The Arrow Head (Fill)
        ArrowHeadShape()
          .fill(color)
          .scaleEffect(arrowHeadScale, anchor: UnitPoint(x: 33.4943 / 56.0, y: 10.7721 / 60.0))
          .opacity(arrowHeadOpacity)
          .offset(x: offsetX, y: offsetY)
      }
    }
    .aspectRatio(56 / 60, contentMode: .fit)
    .onAppear {
      // Reset state first in case of re-appearance
      drawingProgress = 0.0
      arrowHeadScale = 0.0
      arrowHeadOpacity = 0.0

      // Animate the line drawing
      withAnimation(.easeInOut(duration: 0.8).delay(0.8)) {
        drawingProgress = 1.0
      }

      // Animate the arrow head popping in near the end
      withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(1.4)) {
        arrowHeadScale = 1.0
        arrowHeadOpacity = 1.0
      }
    }
  }
}

private struct ArrowLineShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    // M8.56738 54.5435
    path.move(to: CGPoint(x: 8.56738, y: 54.5435))
    // C16.9752 55.2122 57.903 59.3481 51.49 30.7579
    path.addCurve(
      to: CGPoint(x: 51.49, y: 30.7579), control1: CGPoint(x: 16.9752, y: 55.2122),
      control2: CGPoint(x: 57.903, y: 59.3481))
    // C48.444 17.178 41.6037 13.4574 33.4943 10.7721
    path.addCurve(
      to: CGPoint(x: 33.4943, y: 10.7721), control1: CGPoint(x: 48.444, y: 17.178),
      control2: CGPoint(x: 41.6037, y: 13.4574))

    // Scale path to fit the rect (assuming rect is the full size we want to draw into, but we want to respect the 56x60 coordinate space)
    // Actually, the Shape is inside a GeometryReader which calculates scale.
    // But Shape.path(in:) receives the rect of the view.
    // If we apply .offset and .scale on the View, we don't need to transform here?
    // Wait, in the body I calculated scale and offset.
    // If I apply .frame(width: 56 * scale, height: 60 * scale) to the shape, then the shape's rect will be that size.
    // But I didn't do that. I just put it in ZStack.
    // Let's make the Shape return the path in 56x60 coordinates, and then apply transformEffect to the shape view.

    return path
  }
}

private struct ArrowHeadShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    // M29.1083 7.59851
    path.move(to: CGPoint(x: 29.1083, y: 7.59851))
    // C27.9837 8.05486 27.442 9.33647 27.8983 10.4611
    path.addCurve(
      to: CGPoint(x: 27.8983, y: 10.4611), control1: CGPoint(x: 27.9837, y: 8.05486),
      control2: CGPoint(x: 27.442, y: 9.33647))
    // L35.335 28.7874
    path.addLine(to: CGPoint(x: 35.335, y: 28.7874))
    // C35.7913 29.912 37.0729 30.4537 38.1975 29.9973
    path.addCurve(
      to: CGPoint(x: 38.1975, y: 29.9973), control1: CGPoint(x: 35.7913, y: 29.912),
      control2: CGPoint(x: 37.0729, y: 30.4537))
    // C39.3221 29.541 39.8639 28.2594 39.4075 27.1348
    path.addCurve(
      to: CGPoint(x: 39.4075, y: 27.1348), control1: CGPoint(x: 39.3221, y: 29.541),
      control2: CGPoint(x: 39.8639, y: 28.2594))
    // L32.7971 10.8447
    path.addLine(to: CGPoint(x: 32.7971, y: 10.8447))
    // L49.0872 4.23435
    path.addLine(to: CGPoint(x: 49.0872, y: 4.23435))
    // C50.2118 3.778 50.7535 2.49639 50.2971 1.37179
    path.addCurve(
      to: CGPoint(x: 50.2971, y: 1.37179), control1: CGPoint(x: 50.2118, y: 3.778),
      control2: CGPoint(x: 50.7535, y: 2.49639))
    // C49.8408 0.247199 48.5592 -0.294519 47.4346 0.161832
    path.addCurve(
      to: CGPoint(x: 47.4346, y: 0.161832), control1: CGPoint(x: 49.8408, y: 0.247199),
      control2: CGPoint(x: 48.5592, y: -0.294519))
    // L29.1083 7.59851
    path.addLine(to: CGPoint(x: 29.1083, y: 7.59851))
    path.closeSubpath()

    // Hole
    // M32.6334 10.7755
    path.move(to: CGPoint(x: 32.6334, y: 10.7755))
    // L33.489 8.7514
    path.addLine(to: CGPoint(x: 33.489, y: 8.7514))
    // L30.7901 7.61063
    path.addLine(to: CGPoint(x: 30.7901, y: 7.61063))
    // L29.9346 9.63477
    path.addLine(to: CGPoint(x: 29.9346, y: 9.63477))
    // L29.079 11.6589
    path.addLine(to: CGPoint(x: 29.079, y: 11.6589))
    // L31.7778 12.7997
    path.addLine(to: CGPoint(x: 31.7778, y: 12.7997))
    // L32.6334 10.7755
    path.addLine(to: CGPoint(x: 32.6334, y: 10.7755))
    path.closeSubpath()

    return path
  }
}

#Preview {
  AnimatedArrowView()
    .frame(width: 100, height: 100)
}
