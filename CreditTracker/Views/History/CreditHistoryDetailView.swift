import SwiftUI
import SwiftData

struct CreditHistoryDetailView: View {
    let credit: Credit
    let card: Card

    private var sortedLogs: [PeriodLog] {
        credit.periodLogs.sorted { $0.periodStart > $1.periodStart }
    }

    private var startColor: Color { Color(hex: card.gradientStartHex) }
    private var endColor: Color { Color(hex: card.gradientEndHex) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Header card
                AtmosphericCardView(
                    gradientStart: startColor,
                    gradientEnd: endColor,
                    gradientOpacity: 0.20
                ) {
                    HStack(spacing: 16) {
                        ChunkyProgressRing(
                            fraction: currentFillFraction,
                            gradientStart: startColor,
                            gradientEnd: endColor,
                            strokeWidth: 8,
                            size: 64
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(credit.name)
                                .font(.system(size: 22, weight: .semibold))
                            Text("$\(String(format: "%.0f", credit.totalValue)) \(credit.timeframeType.displayName)")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                            Text("Reminder: \(credit.reminderDaysBefore) days before")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                }

                // Period log entries
                if sortedLogs.isEmpty {
                    Text("No history yet")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                } else {
                    ForEach(sortedLogs) { log in
                        periodLogRow(log)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(hex: "#0A0A0F"))
        .navigationTitle(credit.name)
        .navigationBarTitleDisplayMode(.large)
    }

    private var currentFillFraction: Double {
        PeriodEngine.activePeriodLog(for: credit)?.fillFraction ?? 0
    }

    @ViewBuilder
    private func periodLogRow(_ log: PeriodLog) -> some View {
        AtmosphericCardView(
            gradientStart: startColor,
            gradientEnd: endColor,
            gradientOpacity: 0.06
        ) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(log.periodLabel)
                        .font(.system(size: 15, weight: .medium))
                    Text("\(DateHelpers.shortDateString(log.periodStart)) – \(DateHelpers.shortDateString(log.periodEnd))")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    GlassStatusPill(status: log.periodStatus)
                    if log.claimedAmount > 0 {
                        Text("$\(String(format: "%.2f", log.claimedAmount))")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
