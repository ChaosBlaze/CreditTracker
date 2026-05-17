import SwiftUI

struct CardThumbnail: View {
    let card: Card
    var size: CGFloat = 40

    private var width: CGFloat { size * 1.58 }
    private var startColor: Color { Color(hex: card.gradientStartHex) }
    private var endColor: Color { Color(hex: card.gradientEndHex) }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.18)
            .fill(
                LinearGradient(
                    colors: [startColor, endColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: width, height: size * 0.625)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.18)
                    .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
    }
}

#Preview {
    let card = Card(
        name: "Amex Gold",
        annualFee: 250,
        gradientStartHex: "#B76E79",
        gradientEndHex: "#C9A96E"
    )
    HStack(spacing: 16) {
        CardThumbnail(card: card, size: 32)
        CardThumbnail(card: card, size: 40)
    }
    .padding()
    .background(CT.background)
}
