import SwiftUI
import SwiftData

struct CreditRowView: View {
    let credit: Credit
    let card: Card

    @State private var showLogModal = false
    @State private var openHapticTrigger = false

    private var activePeriod: PeriodLog? {
        PeriodEngine.activePeriodLog(for: credit)
    }
    private var startColor: Color { Color(hex: card.gradientStartHex) }
    private var endColor: Color { Color(hex: card.gradientEndHex) }

    var body: some View {
        Button {
            openHapticTrigger.toggle()
            showLogModal = true
        } label: {
            HStack(spacing: 12) {
                // Progress ring
                ProgressRingView(
                    fraction: activePeriod?.fillFraction ?? 0,
                    startColor: startColor,
                    endColor: endColor,
                    lineWidth: 5,
                    size: 46
                )

                // Credit info
                VStack(alignment: .leading, spacing: 3) {
                    Text(credit.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        if let period = activePeriod {
                            Text(period.periodLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            StatusPill(status: period.periodStatus)
                        }
                    }
                }

                Spacer()

                // Value & timeframe
                VStack(alignment: .trailing, spacing: 2) {
                    if let period = activePeriod {
                        Text("$\(Int(period.claimedAmount)) / $\(Int(credit.totalValue))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("$\(Int(credit.totalValue))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(credit.timeframeType.displayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: openHapticTrigger)
        .sheet(isPresented: $showLogModal) {
            CreditLoggingView(credit: credit, card: card)
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
        }
    }
}
