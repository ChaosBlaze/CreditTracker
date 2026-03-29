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
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        ProgressRingView(
                            fraction: currentFillFraction,
                            startColor: startColor,
                            endColor: endColor,
                            lineWidth: 7,
                            size: 64
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(credit.name)
                                .font(.headline)
                            Text("$\(String(format: "%.0f", credit.totalValue)) \(credit.timeframeType.displayName)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Reminder: \(credit.reminderDaysBefore) days before")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Log History") {
                    if sortedLogs.isEmpty {
                        Text("No history yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedLogs) { log in
                            periodLogRow(log)
                        }
                    }
                }
            }
            .navigationTitle(credit.name)
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var currentFillFraction: Double {
        PeriodEngine.activePeriodLog(for: credit)?.fillFraction ?? 0
    }

    @ViewBuilder
    private func periodLogRow(_ log: PeriodLog) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(log.periodLabel)
                    .font(.subheadline.weight(.medium))
                Text("\(DateHelpers.shortDateString(log.periodStart)) – \(DateHelpers.shortDateString(log.periodEnd))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                StatusPill(status: log.periodStatus)
                if log.claimedAmount > 0 {
                    Text("$\(String(format: "%.2f", log.claimedAmount))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
