import SwiftUI

/// Horizontal step indicator for Bonuses.
/// Circles connected by lines. Completed = filled green + checkmark.
/// Current = pulsing accent. Future = hollow gray.
struct StepProgressView: View {
    let steps: [BonusStep]
    let currentStep: Int
    let accentColor: Color

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                // Step circle
                stepCircle(index: index, step: step)

                // Connecting line (except after last step)
                if index < steps.count - 1 {
                    connectingLine(afterIndex: index)
                }
            }
        }
    }

    @ViewBuilder
    private func stepCircle(index: Int, step: BonusStep) -> some View {
        let isCompleted = index < currentStep
        let isCurrent = index == currentStep
        let isFuture = index > currentStep

        ZStack {
            if isCompleted {
                Circle()
                    .fill(Color.green)
                    .frame(width: 28, height: 28)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            } else if isCurrent {
                // Pulsing accent circle
                Circle()
                    .fill(accentColor.opacity(0.2))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Circle()
                            .strokeBorder(accentColor, lineWidth: 2.5)
                    }
                    .modifier(PulsingScaleModifier())

                Image(systemName: step.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentColor)
            } else {
                Circle()
                    .strokeBorder(Color.gray.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 28, height: 28)
                Image(systemName: step.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 34, height: 34)
    }

    @ViewBuilder
    private func connectingLine(afterIndex index: Int) -> some View {
        let isCompleted = index < currentStep

        Rectangle()
            .fill(isCompleted ? Color.green : Color.gray.opacity(0.3))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }
}

struct BonusStep {
    let label: String
    let icon: String
}

private struct PulsingScaleModifier: ViewModifier {
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    scale = 1.1
                }
            }
    }
}
