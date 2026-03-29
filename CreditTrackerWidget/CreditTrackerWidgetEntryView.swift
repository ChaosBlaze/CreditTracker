import SwiftUI
import WidgetKit
import Charts

struct CreditTrackerWidgetEntryView: View {
    let entry: ROIEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        default:
            mediumView
        }
    }

    // MARK: - Small Widget

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "creditcard.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Credit ROI")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text("$\(String(format: "%.0f", entry.totalExtracted))")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(entry.isPositive ? Color.green : Color.orange)
                Text("of $\(String(format: "%.0f", entry.totalFees)) fees")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Image(systemName: entry.isPositive ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(entry.isPositive ? Color.green : Color.red)
                Text(entry.isPositive
                     ? "+$\(String(format: "%.0f", entry.netROI))"
                     : "-$\(String(format: "%.0f", abs(entry.netROI)))")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(entry.isPositive ? Color.green : Color.red)
                Spacer()
            }
        }
        .padding(14)
        .containerBackground(
            LinearGradient(
                colors: [Color.teal.opacity(0.18), Color.green.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            for: .widget
        )
    }

    // MARK: - Medium Widget

    private var mediumView: some View {
        HStack(spacing: 16) {
            // Left: stats
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "creditcard.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Credit ROI")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    statRow(label: "Fees", value: "$\(String(format: "%.0f", entry.totalFees))", color: .secondary)
                    statRow(label: "Extracted", value: "$\(String(format: "%.0f", entry.totalExtracted))",
                            color: entry.isPositive ? Color.green : Color.orange)
                    statRow(
                        label: "Net",
                        value: (entry.isPositive ? "+" : "") + "$\(String(format: "%.0f", entry.netROI))",
                        color: entry.isPositive ? Color.green : Color.red
                    )
                }

                Spacer()

                Text("\(entry.cardCount) card\(entry.cardCount == 1 ? "" : "s") tracked")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 110, alignment: .leading)

            Divider()
                .padding(.vertical, 8)

            // Right: chart
            VStack(alignment: .leading, spacing: 4) {
                Text("Monthly")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                if entry.monthlyData.isEmpty {
                    Spacer()
                    Text("No data yet")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else {
                    Chart(entry.monthlyData) { item in
                        BarMark(
                            x: .value("Month", item.label),
                            y: .value("Value", item.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.green.opacity(0.85), Color.teal.opacity(0.6)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .cornerRadius(3)
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(.system(size: 7))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .padding(14)
        .containerBackground(
            LinearGradient(
                colors: [Color.teal.opacity(0.18), Color.green.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            for: .widget
        )
    }

    @ViewBuilder
    private func statRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
    }
}

#Preview(as: .systemSmall) {
    CreditTrackerWidget()
} timeline: {
    ROIEntry.placeholder
}

#Preview(as: .systemMedium) {
    CreditTrackerWidget()
} timeline: {
    ROIEntry.placeholder
}
