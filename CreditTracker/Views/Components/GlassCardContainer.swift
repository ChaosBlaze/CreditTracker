import SwiftUI

struct GlassCardContainer<Content: View>: View {
    let startHex: String
    let endHex: String
    @ViewBuilder let content: Content

    private var startColor: Color { Color(hex: startHex) }
    private var endColor: Color { Color(hex: endHex) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Vivid gradient tint bleeds through the glass surface
            LinearGradient(
                colors: [startColor.opacity(0.65), endColor.opacity(0.50)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            content
                .padding(16)
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: startColor.opacity(0.30), radius: 10, x: 0, y: 4)
    }
}

// Fallback version without glassEffect (for previews / older toolchains)
struct GlassCardContainerFallback<Content: View>: View {
    let startHex: String
    let endHex: String
    @ViewBuilder let content: Content

    private var startColor: Color { Color(hex: startHex) }
    private var endColor: Color { Color(hex: endHex) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [startColor.opacity(0.15), endColor.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)

            content
                .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
