import SwiftUI

struct CollapsedCardRow: View {
    let card: Card

    var body: some View {
        HStack(spacing: 12) {
            CardThumbnail(card: card, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(card.name)
                    .font(.ctRowTitle)
                    .foregroundStyle(CT.ink)

                SegmentPipRow(credits: card.credits)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CT.ink4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(CT.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(CT.hairline.opacity(0.6), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    let card = Card(
        name: "Amex Gold",
        annualFee: 250,
        gradientStartHex: "#B76E79",
        gradientEndHex: "#C9A96E"
    )
    CollapsedCardRow(card: card)
        .padding()
        .background(CT.background)
}
