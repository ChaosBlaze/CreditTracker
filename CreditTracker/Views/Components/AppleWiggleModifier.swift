import SwiftUI

// MARK: - AppleWiggleModifier

/// A `ViewModifier` that applies an organic, asynchronous "jiggle" animation
/// identical to the iOS Home Screen edit mode.
///
/// ## Organic Design Principles
/// The key to feeling authentic (not robotic) is that every card on screen
/// must differ in three independent ways:
///
/// 1. **Rotation magnitude** — each card tilts a slightly different amount (±0.9° – ±1.5°).
/// 2. **Speed** — each card completes one half-swing in a slightly different time (100 – 170 ms).
/// 3. **Phase offset** — a random stagger delay (0 – 140 ms) ensures no two cards start
///    their wiggle at the same moment, so they fall in and out of sync naturally.
///
/// The rotation is a true pendulum: the card snaps to one extreme without animation,
/// then `repeatForever(autoreverses: true)` carries it to the opposite extreme and back,
/// producing the full ±angle swing from the very first frame.
///
/// A subtle white stroke overlay appears while wiggling to signal that the cards
/// are interactive / draggable without any text instruction.
struct AppleWiggleModifier: ViewModifier {

    let isWiggling: Bool

    // MARK: - Live Animation State

    /// Current rotation angle driven by the `repeatForever` animation.
    @State private var rotation: Double = 0

    /// Subtle horizontal tremor — adds tactile realism without visual noise.
    @State private var xOffset: CGFloat = 0

    // MARK: - Fixed Random Parameters (seeded once on `.onAppear`)

    /// Peak rotation angle (positive extreme of the pendulum), in degrees.
    @State private var rotationMagnitude: Double = 1.2

    /// Duration of one half-swing. Shorter = snappier; longer = lazier.
    @State private var wiggleDuration: Double = 0.13

    /// Stagger delay before the animation starts. Desynchronizes cards.
    @State private var startDelay: TimeInterval = 0.0

    // MARK: - Body

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation), anchor: .center)
            .offset(x: xOffset)
            // Interactive stroke — fades in when wiggling to hint at draggability.
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        .white.opacity(isWiggling ? 0.28 : 0),
                        lineWidth: 1.5
                    )
                    .animation(.easeInOut(duration: 0.25), value: isWiggling)
            }
            // React to edit mode toggle.
            .onChange(of: isWiggling) { _, nowWiggling in
                if nowWiggling { scheduleWiggleStart() }
                else           { snapToRest() }
            }
            // Seed random parameters exactly once per view lifetime.
            .onAppear {
                rotationMagnitude = Double.random(in: 0.9...1.5)
                wiggleDuration    = Double.random(in: 0.10...0.17)
                startDelay        = Double.random(in: 0.00...0.14)
                if isWiggling { scheduleWiggleStart() }
            }
    }

    // MARK: - Animation Helpers

    /// Stagger-starts the pendulum animation to desynchronize cards on screen.
    private func scheduleWiggleStart() {
        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
            // Guard: edit mode may have already been cancelled during the delay.
            guard isWiggling else { return }

            // Snap to one extreme *without* animation so the `repeatForever` pendulum
            // covers the full ± magnitude arc from frame 1, not just 0 → magnitude.
            rotation = -rotationMagnitude
            xOffset  = -0.4

            withAnimation(
                .easeInOut(duration: wiggleDuration)
                .repeatForever(autoreverses: true)
            ) {
                rotation = rotationMagnitude
                xOffset  = 0.4
            }
        }
    }

    /// Returns the card smoothly to its natural resting position.
    private func snapToRest() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
            rotation = 0
            xOffset  = 0
        }
    }
}

// MARK: - View Extension

extension View {
    /// Applies the Apple Home Screen-style organic wiggle animation when `isActive` is true.
    ///
    /// Each view that calls this modifier independently randomizes its wiggle parameters,
    /// so even identical sibling views will desynchronize naturally.
    func wiggling(isActive: Bool) -> some View {
        modifier(AppleWiggleModifier(isWiggling: isActive))
    }
}
