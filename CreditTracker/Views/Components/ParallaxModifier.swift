import SwiftUI
import CoreMotion

/// ViewModifier using CMMotionManager to apply subtle X/Y offset based on device tilt.
/// Falls back to no-op in Simulator.
struct ParallaxModifier: ViewModifier {
    let magnitude: CGFloat

    @StateObject private var motion = MotionManager.shared

    func body(content: Content) -> some View {
        content
            .offset(
                x: motion.xOffset * magnitude,
                y: motion.yOffset * magnitude
            )
            .animation(.interpolatingSpring(stiffness: 50, damping: 12), value: motion.xOffset)
            .animation(.interpolatingSpring(stiffness: 50, damping: 12), value: motion.yOffset)
    }
}

extension View {
    func parallaxEffect(magnitude: CGFloat = 10) -> some View {
        modifier(ParallaxModifier(magnitude: magnitude))
    }
}

/// Shared motion manager singleton to avoid multiple CMMotionManager instances
@MainActor
final class MotionManager: ObservableObject {
    static let shared = MotionManager()

    @Published var xOffset: CGFloat = 0
    @Published var yOffset: CGFloat = 0

    private let motionManager = CMMotionManager()
    private var referenceCount = 0

    private init() {
        #if !targetEnvironment(simulator)
        startMotionUpdates()
        #endif
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion = motion, let self = self else { return }
            Task { @MainActor in
                self.xOffset = CGFloat(motion.gravity.x)
                self.yOffset = CGFloat(motion.gravity.y)
            }
        }
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}
