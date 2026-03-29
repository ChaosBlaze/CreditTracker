import SwiftUI

/// Semicircular gauge for History tab showing net ROI.
/// Arc gradient from red (negative) -> yellow (break-even) -> green (positive).
/// Animated needle with spring.
struct ROIGaugeView: View {
    let currentROI: Double
    let maxScale: Double
    var size: CGFloat = 200

    @State private var animatedFraction: Double = 0.5

    private var targetFraction: Double {
        // Map ROI from [-maxScale, +maxScale] to [0, 1]
        let clamped = min(max(currentROI, -maxScale), maxScale)
        return (clamped + maxScale) / (2 * maxScale)
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Arc track (red -> yellow -> green)
                ArcShape(startAngle: .degrees(180), endAngle: .degrees(360))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                .red,
                                .red.opacity(0.8),
                                .orange,
                                .yellow,
                                .green.opacity(0.8),
                                .green
                            ]),
                            center: .center,
                            startAngle: .degrees(180),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: size, height: size / 2)

                // Track background
                ArcShape(startAngle: .degrees(180), endAngle: .degrees(360))
                    .stroke(
                        Color.gray.opacity(0.15),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .frame(width: size, height: size / 2)
                    .blendMode(.destinationOver)

                // Needle
                NeedleShape()
                    .fill(Color.white)
                    .frame(width: 3, height: size / 2 - 20)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                    .offset(y: -(size / 4 - 10))
                    .rotationEffect(.degrees(-90 + animatedFraction * 180))

                // Center dot
                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                    .shadow(color: .black.opacity(0.2), radius: 2)

                // Labels
                HStack {
                    Text("-$\(formattedScale)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.6))

                    Spacer()

                    Text("+$\(formattedScale)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.6))
                }
                .frame(width: size + 10)
                .offset(y: size / 4 + 4)
            }
            .frame(width: size, height: size / 2 + 16)

            // Motivational text
            Text(motivationalText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(currentROI >= 0 ? .green : .orange)
                .multilineTextAlignment(.center)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) {
                animatedFraction = targetFraction
            }
        }
        .onChange(of: currentROI) { _, _ in
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) {
                animatedFraction = targetFraction
            }
        }
    }

    private var motivationalText: String {
        if currentROI >= 0 {
            return "You're $\(Int(currentROI)) ahead!"
        } else {
            return "You're $\(Int(abs(currentROI))) away from breaking even"
        }
    }

    private var formattedScale: String {
        if maxScale >= 1000 {
            return "\(Int(maxScale / 1000))K"
        }
        return "\(Int(maxScale))"
    }
}

struct ArcShape: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = min(rect.width, rect.height * 2) / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

struct NeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w / 2, y: 0))
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}
