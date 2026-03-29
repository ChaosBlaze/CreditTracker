import SwiftUI

/// Reusable atmospheric card surface implementing the full card recipe:
/// material + gradient bleed + noise texture + inner glow + shadow
struct AtmosphericCardView<Content: View>: View {
    let gradientStart: Color
    let gradientEnd: Color
    var gradientOpacity: Double = 0.15
    var cornerRadius: CGFloat = 20
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .background {
                ZStack {
                    // 1. Base material
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // 2. Gradient bleed
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    gradientStart.opacity(gradientOpacity),
                                    gradientEnd.opacity(gradientOpacity * 0.33)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // 3. Noise texture overlay (generated procedurally)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.white.opacity(0.03))
                        .overlay {
                            NoiseTextureView()
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                                .opacity(0.05)
                        }

                    // 4. Inner glow stroke
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.15), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
            // 5. Shadow
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
    }
}

/// Convenience initializer using hex strings
extension AtmosphericCardView {
    init(
        startHex: String,
        endHex: String,
        gradientOpacity: Double = 0.15,
        cornerRadius: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) {
        self.gradientStart = Color(hex: startHex)
        self.gradientEnd = Color(hex: endHex)
        self.gradientOpacity = gradientOpacity
        self.cornerRadius = cornerRadius
        self.content = content()
    }
}

/// Procedural noise texture using Canvas
struct NoiseTextureView: View {
    var body: some View {
        Canvas { context, size in
            // Draw a simple noise pattern
            let step: CGFloat = 2
            var x: CGFloat = 0
            while x < size.width {
                var y: CGFloat = 0
                while y < size.height {
                    let hash = pseudoRandom(x: Int(x / step), y: Int(y / step))
                    if hash > 0.5 {
                        context.fill(
                            Path(CGRect(x: x, y: y, width: step, height: step)),
                            with: .color(.white.opacity(Double(hash) * 0.3))
                        )
                    }
                    y += step
                }
                x += step
            }
        }
    }

    private func pseudoRandom(x: Int, y: Int) -> Float {
        var seed = UInt32(truncatingIfNeeded: x &* 374761393 &+ y &* 668265263)
        seed = (seed ^ (seed >> 13)) &* 1274126177
        seed = seed ^ (seed >> 16)
        return Float(seed) / Float(UInt32.max)
    }
}
