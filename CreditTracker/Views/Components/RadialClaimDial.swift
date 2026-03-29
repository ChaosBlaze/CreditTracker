import SwiftUI

/// The signature radial dial component for claiming credits.
/// A large frosted glass circle with tick marks around the circumference.
/// Drag the handle clockwise to increase, counterclockwise to decrease.
struct RadialClaimDial: View {
    let maxAmount: Double
    @Binding var currentAmount: Double
    let accentStart: Color
    let accentEnd: Color
    var tickIncrement: Double? = nil
    var dialSize: CGFloat = 200

    @State private var dragAngle: Double = 0
    @State private var lastTickAngle: Double = -1
    @GestureState private var isDragging = false

    private var computedTickIncrement: Double {
        if let tick = tickIncrement { return tick }
        if maxAmount <= 20 { return 1 }
        if maxAmount <= 100 { return 5 }
        return 10
    }

    private var fraction: Double {
        guard maxAmount > 0 else { return 0 }
        return min(currentAmount / maxAmount, 1.0)
    }

    private var tickCount: Int {
        max(Int(maxAmount / computedTickIncrement), 1)
    }

    var body: some View {
        ZStack {
            // Dial background - frosted glass circle
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentStart.opacity(0.10), accentEnd.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }

            // Tick marks around circumference
            ForEach(0..<tickCount, id: \.self) { i in
                let angle = (Double(i) / Double(tickCount)) * 360 - 90
                let isFilled = Double(i) / Double(tickCount) <= fraction

                Rectangle()
                    .fill(isFilled ? accentStart : Color.gray.opacity(0.3))
                    .frame(width: 2, height: isFilled ? 10 : 6)
                    .offset(y: -(dialSize / 2 - 14))
                    .rotationEffect(.degrees(angle))
            }

            // Progress arc
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [accentStart, accentEnd]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: dialSize - 36, height: dialSize - 36)

            // Center amount display
            VStack(spacing: 2) {
                Text("$\(formattedAmount)")
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())

                Text("of $\(formattedMax)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Draggable handle
            Circle()
                .fill(.white)
                .frame(width: 24, height: 24)
                .shadow(color: accentStart.opacity(0.5), radius: 6, y: 2)
                .overlay {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentStart, accentEnd],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(3)
                }
                .offset(y: -(dialSize / 2 - 18))
                .rotationEffect(.degrees(fraction * 360 - 90))
                .gesture(dragGesture)
                .scaleEffect(isDragging ? 1.2 : 1.0)
                .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.6), value: isDragging)
        }
        .frame(width: dialSize, height: dialSize)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                let center = CGPoint(x: dialSize / 2, y: dialSize / 2)
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                var angle = atan2(dy, dx) * 180 / .pi + 90
                if angle < 0 { angle += 360 }

                let newFraction = angle / 360.0
                let newAmount = round(newFraction * maxAmount / computedTickIncrement) * computedTickIncrement
                let clampedAmount = min(max(newAmount, 0), maxAmount)

                // Per-tick haptic
                let tickAngle = round(angle / (360.0 / Double(tickCount)))
                if tickAngle != lastTickAngle {
                    lastTickAngle = tickAngle
                    if clampedAmount >= maxAmount {
                        HapticEngine.shared.dialSnapToMax()
                    } else {
                        HapticEngine.shared.dialTick()
                    }
                }

                withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.6)) {
                    currentAmount = clampedAmount
                }
            }
    }

    private var formattedAmount: String {
        if currentAmount == floor(currentAmount) {
            return String(Int(currentAmount))
        }
        return String(format: "%.2f", currentAmount)
    }

    private var formattedMax: String {
        if maxAmount == floor(maxAmount) {
            return String(Int(maxAmount))
        }
        return String(format: "%.2f", maxAmount)
    }
}
