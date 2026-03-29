import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Query(sort: \Card.sortOrder) private var cards: [Card]
    @State private var expandedCards: Set<UUID> = []
    @State private var expandHapticTrigger = false

    var body: some View {
        NavigationStack {
            List {
                // ROI Dashboard at the top
                if !cards.isEmpty {
                    Section {
                        ROIDashboardView(cards: cards)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                    }
                }

                if cards.isEmpty {
                    emptyState
                } else {
                    ForEach(cards) { card in
                        CardHistorySection(
                            card: card,
                            isExpanded: expandedCards.contains(card.id)
                        ) {
                            expandHapticTrigger.toggle()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if expandedCards.contains(card.id) {
                                    expandedCards.remove(card.id)
                                } else {
                                    expandedCards.insert(card.id)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("History")
            .sensoryFeedback(.selection, trigger: expandHapticTrigger)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No history yet")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .padding(.top, 60)
    }
}

// MARK: - ROI Dashboard

struct MonthlyROI: Identifiable {
    let id = UUID()
    let month: Date
    let label: String
    let value: Double
}

struct ROIDashboardView: View {
    let cards: [Card]

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var totalFees: Double {
        cards.reduce(0) { $0 + $1.annualFee }
    }

    private var totalExtracted: Double {
        cards.flatMap { $0.credits }.reduce(0) { $0 + PeriodEngine.totalClaimedThisYear(for: $1) }
    }

    private var netROI: Double { totalExtracted - totalFees }
    private var isPositive: Bool { netROI >= 0 }

    private var monthlyData: [MonthlyROI] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        return (1...12).compactMap { month -> MonthlyROI? in
            guard let date = calendar.date(from: DateComponents(year: currentYear, month: month)) else { return nil }
            var total = 0.0
            for card in cards {
                for credit in card.credits {
                    for log in credit.periodLogs {
                        let logYear = calendar.component(.year, from: log.periodStart)
                        let logMonth = calendar.component(.month, from: log.periodStart)
                        if logYear == currentYear && logMonth == month {
                            total += log.claimedAmount
                        }
                    }
                }
            }
            guard total > 0 else { return nil }
            return MonthlyROI(month: date, label: formatter.string(from: date), value: total)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(currentYear) Year in Review")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Fees paid vs. value extracted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isPositive ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isPositive ? Color.green : Color.red)
            }

            // Fee vs Value stats row
            HStack(spacing: 0) {
                roiStatBlock(
                    title: "Annual Fees",
                    value: "$\(String(format: "%.0f", totalFees))",
                    color: .secondary,
                    systemImage: "creditcard"
                )

                Divider()
                    .frame(height: 44)
                    .padding(.horizontal, 16)

                roiStatBlock(
                    title: "Value Extracted",
                    value: "$\(String(format: "%.0f", totalExtracted))",
                    color: totalExtracted >= totalFees ? Color.green : Color.orange,
                    systemImage: "dollarsign.circle"
                )

                Divider()
                    .frame(height: 44)
                    .padding(.horizontal, 16)

                roiStatBlock(
                    title: "Net ROI",
                    value: (isPositive ? "+" : "") + "$\(String(format: "%.0f", netROI))",
                    color: isPositive ? Color.green : Color.red,
                    systemImage: isPositive ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis"
                )
            }

            // Swift Charts bar graph
            if !monthlyData.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Monthly Value")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Chart(monthlyData) { entry in
                        BarMark(
                            x: .value("Month", entry.label),
                            y: .value("Value", entry.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.green.opacity(0.9), Color.teal.opacity(0.7)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .cornerRadius(5)
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("$\(Int(v))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                                .foregroundStyle(.secondary.opacity(0.3))
                        }
                    }
                    .frame(height: 120)
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("No value extracted yet this year")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .padding(20)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func roiStatBlock(title: String, value: String, color: Color, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .labelStyle(.titleOnly)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Card History Section

struct CardHistorySection: View {
    let card: Card
    let isExpanded: Bool
    let onTap: () -> Void

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var totalClaimedThisYear: Double {
        card.credits.reduce(0) { $0 + PeriodEngine.totalClaimedThisYear(for: $1) }
    }

    private var netROI: Double {
        totalClaimedThisYear - card.annualFee
    }

    private var startColor: Color { Color(hex: card.gradientStartHex) }
    private var endColor: Color { Color(hex: card.gradientEndHex) }

    var body: some View {
        Section {
            // Header row
            Button(action: onTap) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [startColor, endColor], startPoint: .top, endPoint: .bottom))
                        .frame(width: 4, height: 36)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        HStack(spacing: 8) {
                            Text("Fee: $\(Int(card.annualFee))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Claimed: $\(String(format: "%.0f", totalClaimedThisYear))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(netROI >= 0 ? "+$\(String(format: "%.0f", netROI))" : "-$\(String(format: "%.0f", abs(netROI)))")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(netROI >= 0 ? Color.green : Color.red)
                        Text("Net ROI \(currentYear)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
            }
            .buttonStyle(.plain)

            // Credits breakdown
            if isExpanded {
                ForEach(card.credits.sorted { $0.name < $1.name }) { credit in
                    NavigationLink {
                        CreditHistoryDetailView(credit: credit, card: card)
                    } label: {
                        CreditHistorySummaryRow(credit: credit, card: card)
                    }
                }
            }
        }
    }
}

struct CreditHistorySummaryRow: View {
    let credit: Credit
    let card: Card

    private var totalClaimedThisYear: Double {
        PeriodEngine.totalClaimedThisYear(for: credit)
    }

    private var activePeriod: PeriodLog? {
        PeriodEngine.activePeriodLog(for: credit)
    }

    var body: some View {
        HStack(spacing: 10) {
            ProgressRingView(
                fraction: activePeriod?.fillFraction ?? 0,
                startColor: Color(hex: card.gradientStartHex),
                endColor: Color(hex: card.gradientEndHex),
                lineWidth: 4,
                size: 36
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(credit.name)
                    .font(.subheadline.weight(.medium))
                Text("$\(String(format: "%.0f", totalClaimedThisYear)) claimed this year")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let period = activePeriod {
                StatusPill(status: period.periodStatus)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: [Card.self, Credit.self, PeriodLog.self], inMemory: true)
}
