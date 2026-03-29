import SwiftUI

/// A glass-material surface tinted by the card's gradient colors.
/// Use as a background or overlay container.
struct GradientTintedGlass: View {
    let startHex: String
    let endHex: String
    var cornerRadius: CGFloat = 16

    private var startColor: Color { Color(hex: startHex) }
    private var endColor: Color { Color(hex: endHex) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [startColor.opacity(0.2), endColor.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func gradientTintedGlassBackground(startHex: String, endHex: String, cornerRadius: CGFloat = 16) -> some View {
        self.background(
            GradientTintedGlass(startHex: startHex, endHex: endHex, cornerRadius: cornerRadius)
        )
    }
}

/// Status pill used across the app
struct StatusPill: View {
    let status: PeriodStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: status.pillColor), in: Capsule())
    }
}
