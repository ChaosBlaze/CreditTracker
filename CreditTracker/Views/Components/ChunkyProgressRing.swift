import SwiftUI

/// Chunky progress ring (6pt stroke) with gradient color, track color,
/// and glow effect at 100%. Built with two Circle().trim() shapes
/// (track + fill) and a blurred duplicate behind for the glow.
struct ChunkyProgressRing: View {
    let fraction: Double
    let gradientStart: Color
    let gradientEnd: Color
    var strokeWidth: CGFloat = 6
    var size: CGFloat = 44
    var showLabel: Bool = true

    @State private var animatedFraction: Double = 0

    private var isComplete: Bool { fraction >= 1.0 }

    var body: some View {
        ZStack {
            // Glow effect when 100%
            if isComplete {
                Circle()
                    .trim(from: 0, to: animatedFraction)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [gradientStart, gradientEnd, gradientStart]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .blur(radius: 8)
                    .opacity(0.5)
            }

            // Track ring (dark gray background)
            Circle()
                .stroke(
                    gradientStart.opacity(0.15),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )

            // Fill ring
            Circle()
                .trim(from: 0, to: animatedFraction)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [gradientStart, gradientEnd, gradientStart]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center label
            if showLabel {
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.26, weight: .bold))
                        .foregroundStyle(gradientEnd)
                } else {
                    Text("\(Int(fraction * 100))%")
                        .font(.system(size: size * 0.20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animatedFraction = fraction
            }
        }
        .onChange(of: fraction) { _, newValue in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animatedFraction = newValue
            }
        }
    }
}

extension ChunkyProgressRing {
    init(
        fraction: Double,
        startHex: String,
        endHex: String,
        strokeWidth: CGFloat = 6,
        size: CGFloat = 44,
        showLabel: Bool = true
    ) {
        self.fraction = fraction
        self.gradientStart = Color(hex: startHex)
        self.gradientEnd = Color(hex: endHex)
        self.strokeWidth = strokeWidth
        self.size = size
        self.showLabel = showLabel
    }
}
