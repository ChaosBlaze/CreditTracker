import SwiftUI
import SwiftData

/// Full-screen animated MeshGradient background with 3x3 control points.
/// Colors derived from first two cards' gradients + deep charcoal anchors.
/// Rendered at 30% opacity behind all tab content.
struct MeshGradientBackground: View {
    let cardColors: [(Color, Color)]

    @State private var animationPhase: CGFloat = 0

    private var color0: Color { cardColors.first?.0 ?? Color(hex: "#B76E79") }
    private var color1: Color { cardColors.first?.1 ?? Color(hex: "#C9A96E") }
    private var color2: Color { cardColors.count > 1 ? cardColors[1].0 : Color(hex: "#A8A9AD") }
    private var color3: Color { cardColors.count > 1 ? cardColors[1].1 : Color(hex: "#E8E8E8") }

    private let charcoal = Color(hex: "#0A0A0F")
    private let darkCharcoal = Color(hex: "#060608")

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(t.truncatingRemainder(dividingBy: 24.0) / 24.0)

            MeshGradient(
                width: 3,
                height: 3,
                points: meshPoints(phase: phase),
                colors: [
                    darkCharcoal, charcoal, darkCharcoal,
                    color0.opacity(0.4), charcoal, color2.opacity(0.4),
                    darkCharcoal, color1.opacity(0.3), color3.opacity(0.3)
                ]
            )
            .opacity(0.30)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Lissajous-style drifting control points for organic movement
    private func meshPoints(phase: CGFloat) -> [SIMD2<Float>] {
        let p = phase * .pi * 2

        func drift(_ base: SIMD2<Float>, dx: Float, dy: Float, freq: Float) -> SIMD2<Float> {
            let ox = sin(p * Float(freq)) * dx
            let oy = cos(p * Float(freq) * 1.3) * dy
            return SIMD2(
                min(max(base.x + ox, 0), 1),
                min(max(base.y + oy, 0), 1)
            )
        }

        return [
            SIMD2(0.0, 0.0),
            drift(SIMD2(0.5, 0.0), dx: 0.05, dy: 0.02, freq: 1.0),
            SIMD2(1.0, 0.0),

            drift(SIMD2(0.0, 0.5), dx: 0.02, dy: 0.05, freq: 0.8),
            drift(SIMD2(0.5, 0.5), dx: 0.08, dy: 0.08, freq: 0.6),
            drift(SIMD2(1.0, 0.5), dx: 0.02, dy: 0.05, freq: 0.9),

            SIMD2(0.0, 1.0),
            drift(SIMD2(0.5, 1.0), dx: 0.05, dy: 0.02, freq: 1.1),
            SIMD2(1.0, 1.0)
        ]
    }
}

/// Convenience initializer that extracts colors from cards
extension MeshGradientBackground {
    init(cards: [Card]) {
        let colors = cards.prefix(2).map { card in
            (Color(hex: card.gradientStartHex), Color(hex: card.gradientEndHex))
        }
        self.cardColors = Array(colors)
    }
}
