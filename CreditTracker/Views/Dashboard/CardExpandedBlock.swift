import SwiftUI

struct CardExpandedBlock: View {
    let card: Card

    @State private var logTarget: Credit? = nil
    @State private var openTapTrigger = false

    private var startColor: Color { Color(hex: card.gradientStartHex) }
    private var endColor: Color { Color(hex: card.gradientEndHex) }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                CardThumbnail(card: card, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name)
                        .font(.ctRowTitle)
                        .foregroundStyle(CT.ink)

                    Text("$\(Int(card.annualFee)) annual fee")
                        .font(.ctMeta)
                        .foregroundStyle(CT.ink3)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(CT.hairline.opacity(0.6))
                    .frame(height: 0.5)
            }

            // Credit rows
            VStack(spacing: 0) {
                ForEach(Array(card.credits.enumerated()), id: \.element.id) { index, credit in
                    creditRow(credit: credit, index: index)
                }
            }
        }
        .background(CT.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(CT.hairline.opacity(0.6), lineWidth: 0.5)
        )
        .sheet(item: $logTarget) { credit in
            CreditLoggingView(credit: credit, card: card)
                .presentationDetents([.height(360)])
                .presentationCornerRadius(28)
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func creditRow(credit: Credit, index: Int) -> some View {
        let log = PeriodEngine.activePeriodLog(for: credit)
        let isDone = log?.periodStatus == .claimed

        Button {
            openTapTrigger.toggle()
            logTarget = credit
        } label: {
            HStack(spacing: 12) {
                ProgressRingView(
                    fraction: log?.fillFraction ?? 0,
                    startColor: isDone ? CT.done : startColor,
                    endColor: isDone ? CT.done : endColor,
                    lineWidth: 3,
                    size: 28
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(credit.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isDone ? CT.ink3 : CT.ink)

                    Text(log?.periodLabel ?? credit.timeframeType.displayName)
                        .font(.ctMeta)
                        .foregroundStyle(CT.ink3)
                }

                Spacer()

                if isDone {
                    Text("Done")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(CT.doneBg, in: Capsule())
                        .foregroundStyle(CT.done)
                } else if let log {
                    Text("$\(Int(log.claimedAmount))/$\(Int(credit.totalValue))")
                        .font(.ctMeta)
                        .foregroundStyle(CT.ink3)
                } else {
                    Text("$\(Int(credit.totalValue))")
                        .font(.ctMeta)
                        .foregroundStyle(CT.ink3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if index > 0 {
                    Rectangle()
                        .fill(CT.hairline.opacity(0.6))
                        .frame(height: 0.5)
                        .padding(.leading, 54)
                }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: openTapTrigger)
    }
}

#Preview {
    let card = Card(
        name: "Amex Gold",
        annualFee: 250,
        gradientStartHex: "#B76E79",
        gradientEndHex: "#C9A96E"
    )
    CardExpandedBlock(card: card)
        .padding()
        .background(CT.background)
}
