import SwiftUI

struct ExpiresSoonSection: View {
    let cards: [Card]

    private struct ExpiringItem: Identifiable {
        let id: UUID
        let credit: Credit
        let card: Card
        let log: PeriodLog
        let daysLeft: Int
    }

    private var expiringItems: [ExpiringItem] {
        cards.flatMap { card in
            card.credits.compactMap { credit -> ExpiringItem? in
                guard let log = PeriodEngine.activePeriodLog(for: credit),
                      log.periodStatus != .claimed,
                      log.daysUntilEnd <= 14,
                      log.daysUntilEnd >= 0
                else { return nil }
                return ExpiringItem(
                    id: credit.id,
                    credit: credit,
                    card: card,
                    log: log,
                    daysLeft: log.daysUntilEnd
                )
            }
        }
        .sorted { $0.daysLeft < $1.daysLeft }
        .prefix(2)
        .map { $0 }
    }

    @State private var logTarget: Credit? = nil
    @State private var logCard: Card? = nil

    var body: some View {
        if expiringItems.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("EXPIRES SOON")
                    .font(.ctSectionLabel)
                    .tracking(1.5)
                    .foregroundStyle(CT.ink3)
                    .padding(.horizontal, 4)

                ForEach(expiringItems) { item in
                    Button {
                        logTarget = item.credit
                        logCard = item.card
                    } label: {
                        expiringRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(item: $logTarget) { credit in
                if let card = logCard {
                    CreditLoggingView(credit: credit, card: card)
                        .presentationDetents([.height(360)])
                        .presentationCornerRadius(28)
                        .presentationDragIndicator(.visible)
                }
            }
        }
    }

    @ViewBuilder
    private func expiringRow(item: ExpiringItem) -> some View {
        let isUrgent = item.daysLeft <= 4

        HStack(spacing: 12) {
            CardThumbnail(card: item.card, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.credit.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CT.ink)

                Text(item.card.name)
                    .font(.system(size: 12))
                    .foregroundStyle(CT.ink3)
            }

            Spacer()

            Text("\(item.daysLeft)d left")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isUrgent ? CT.urgentBg : CT.surface2, in: Capsule())
                .foregroundStyle(isUrgent ? CT.urgent : CT.ink3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isUrgent ? CT.urgentBg : CT.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isUrgent ? Color.clear : CT.hairline.opacity(0.6), lineWidth: 0.5)
        )
    }
}

#Preview {
    ExpiresSoonSection(cards: [])
        .padding()
        .background(CT.background)
}
