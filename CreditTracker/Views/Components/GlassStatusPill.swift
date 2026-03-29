import SwiftUI

/// Status capsule with tinted glass background.
/// Supports pulse animation for pending/urgent states.
struct GlassStatusPill: View {
    let label: String
    let icon: String
    let tint: Color
    var pulse: Bool = false

    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(tint.opacity(0.20))
                }
        }
        .clipShape(Capsule())
        .opacity(pulse ? pulseOpacity : 1.0)
        .onAppear {
            if pulse {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseOpacity = 0.7
                }
            }
        }
    }
}

/// Factory to create pills from PeriodStatus
extension GlassStatusPill {
    init(status: PeriodStatus) {
        switch status {
        case .claimed:
            self.init(label: "Claimed", icon: "checkmark", tint: .green)
        case .pending:
            self.init(label: "Pending", icon: "clock", tint: .orange, pulse: true)
        case .partiallyClaimed:
            self.init(label: "Partial", icon: "circle.lefthalf.filled", tint: .blue)
        case .missed:
            self.init(label: "Missed", icon: "xmark", tint: .red)
        }
    }
}
