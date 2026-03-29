import SwiftUI

/// Canvas-based particle system for confetti burst.
/// On trigger, emits 50 particles from origin with physics.
struct ConfettiCanvasView: View {
    @Binding var isActive: Bool
    var origin: CGPoint = CGPoint(x: 0.5, y: 0.8) // Normalized (0-1)
    var accentColors: [Color] = [.red, .green, .blue, .orange, .purple, .yellow]

    @State private var particles: [ConfettiParticle] = []
    @State private var startTime: Date? = nil

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                Canvas { context, size in
                    guard let start = startTime else { return }
                    let elapsed = timeline.date.timeIntervalSince(start)

                    for particle in particles {
                        let t = elapsed - particle.delay
                        guard t > 0 && t < particle.lifetime else { continue }

                        let progress = t / particle.lifetime

                        // Position with gravity (gravity kicks in after 0.3s)
                        var x = particle.startX + particle.velocityX * t
                        var y = particle.startY + particle.velocityY * t
                        if t > 0.3 {
                            let gravityTime = t - 0.3
                            y += 500 * gravityTime * gravityTime * 0.5
                        }

                        // Rotation
                        let rotation = particle.rotationSpeed * t

                        // Opacity fade in final 30%
                        let opacity = progress > 0.7 ? (1.0 - (progress - 0.7) / 0.3) : 1.0

                        // Draw particle
                        var transform = CGAffineTransform.identity
                        transform = transform.translatedBy(x: x, y: y)
                        transform = transform.rotated(by: rotation)

                        context.opacity = opacity
                        context.transform = transform

                        if particle.isCircle {
                            let rect = CGRect(x: -3, y: -3, width: 6, height: 6)
                            context.fill(Circle().path(in: rect), with: .color(particle.color))
                        } else {
                            let rect = CGRect(x: -2, y: -4, width: 4, height: 8)
                            context.fill(Rectangle().path(in: rect), with: .color(particle.color))
                        }

                        context.transform = .identity
                        context.opacity = 1.0
                    }
                }
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    spawnParticles(in: geo.size)
                    // Auto-dismiss after 2.5s
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        isActive = false
                        particles = []
                        startTime = nil
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func spawnParticles(in size: CGSize) {
        let originPt = CGPoint(x: size.width * origin.x, y: size.height * origin.y)
        startTime = Date()

        let allColors = accentColors + [Color(hex: "#FFD700"), Color(hex: "#C0C0C0")]

        particles = (0..<50).map { _ in
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 200...400)

            return ConfettiParticle(
                startX: originPt.x,
                startY: originPt.y,
                velocityX: cos(angle) * speed,
                velocityY: sin(angle) * speed - 150, // Bias upward
                rotationSpeed: Double.random(in: -12.56...12.56), // ±720°/s
                color: allColors.randomElement() ?? .yellow,
                isCircle: Bool.random(),
                lifetime: Double.random(in: 1.5...2.5),
                delay: Double.random(in: 0...0.1)
            )
        }
    }
}

struct ConfettiParticle {
    let startX: Double
    let startY: Double
    let velocityX: Double
    let velocityY: Double
    let rotationSpeed: Double
    let color: Color
    let isCircle: Bool
    let lifetime: Double
    let delay: Double
}
