import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Query(sort: \Card.sortOrder) private var cards: [Card]
    @Query private var statsArray: [UserStats]
    @Query private var achievements: [Achievement]
    @State private var expandedCards: Set<UUID> = []
    @State private var expandHapticTrigger = false
    @State private var selectedYear: Int
    @State private var selectedMonth: Int? = nil
    @State private var showAchievementsSheet = false

    private var stats: UserStats? { statsArray.first }

    init() {
        _selectedYear = State(initialValue: Calendar.current.component(.year, from: Date()))
    }

    private var availableYears: [Int] {
        let allYears = cards.flatMap { $0.credits }
            .flatMap { $0.periodLogs }
            .map { Calendar.current.component(.year, from: $0.periodStart) }
        let unique = Set(allYears)
        return unique.sorted().reversed()
    }

    private var totalFees: Double {
        cards.reduce(0) { $0 + $1.annualFee }
    }

    private var totalExtracted: Double {
        cards.flatMap { $0.credits }.reduce(0) { $0 + PeriodEngine.totalClaimedThisYear(for: $1, year: selectedYear) }
    }

    private var netROI: Double { totalExtracted - totalFees }
    private var isPositive: Bool { netROI >= 0 }

    private var monthlyData: [MonthlyROI] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        return (1...12).compactMap { month -> MonthlyROI? in
            guard let date = calendar.date(from: DateComponents(year: selectedYear, month: month)) else { return nil }
            var total = 0.0
            for card in cards {
                for credit in card.credits {
                    for log in credit.periodLogs {
                        let logYear = calendar.component(.year, from: log.periodStart)
                        let logMonth = calendar.component(.month, from: log.periodStart)
                        if logYear == selectedYear && logMonth == month {
                            total += log.claimedAmount
                        }
                    }
                }
            }
            return MonthlyROI(month: date, label: formatter.string(from: date), value: total, monthNumber: month)
        }
    }

    private var maxROIScale: Double {
        max(abs(netROI) * 1.5, totalFees, 500)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if !cards.isEmpty {
                        // Hero summary card
                        heroSummaryCard

                        // ROI Gauge
                        AtmosphericCardView(
                            gradientStart: isPositive ? .green : .red,
                            gradientEnd: isPositive ? .teal : .orange,
                            gradientOpacity: 0.10
                        ) {
                            ROIGaugeView(
                                currentROI: netROI,
                                maxScale: maxROIScale
                            )
                        }

                        // Area chart
                        chartCard

                        // Month pills
                        monthPillsRow

                        // Your Stats card (gamification)
                        if let stats = stats {
                            statsCard(stats)
                        }

                        // Per-card ROI rows
                        ForEach(cards) { card in
                            cardROIRow(card: card)
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(hex: "#0A0A0F"))
            .navigationTitle("History")
            .sensoryFeedback(.selection, trigger: expandHapticTrigger)
            .sheet(isPresented: $showAchievementsSheet) {
                AchievementsGallerySheet(achievements: achievements)
            }
        }
    }

    // MARK: - Hero Summary Card

    private var heroSummaryCard: some View {
        AtmosphericCardView(
            gradientStart: .purple,
            gradientEnd: .blue,
            gradientOpacity: 0.20
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Year selector
                HStack {
                    Button {
                        if let prev = availableYears.first(where: { $0 < selectedYear }) {
                            withAnimation { selectedYear = prev }
                        } else {
                            withAnimation { selectedYear -= 1 }
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text("\(selectedYear)")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())

                    Button {
                        let currentYear = Calendar.current.component(.year, from: Date())
                        if selectedYear < currentYear {
                            withAnimation { selectedYear += 1 }
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                // Three metric capsules
                HStack(spacing: 8) {
                    metricCapsule(
                        label: "Fees Paid",
                        value: totalFees,
                        color: .white
                    )
                    metricCapsule(
                        label: "Claimed",
                        value: totalExtracted,
                        color: .green
                    )
                    metricCapsule(
                        label: "Net ROI",
                        value: netROI,
                        color: isPositive ? .green : .red,
                        showSign: true
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func metricCapsule(label: String, value: Double, color: Color, showSign: Bool = false) -> some View {
        VStack(spacing: 4) {
            OdometerText(
                value: abs(value),
                prefix: showSign ? (value >= 0 ? "+$" : "-$") : "$",
                font: .system(size: 17, weight: .semibold, design: .monospaced),
                color: AnyShapeStyle(color)
            )

            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        AtmosphericCardView(
            gradientStart: .green.opacity(0.5),
            gradientEnd: .teal.opacity(0.5),
            gradientOpacity: 0.08
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Monthly Value")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                if monthlyData.contains(where: { $0.value > 0 }) {
                    // Gradient area chart
                    Chart(monthlyData) { entry in
                        AreaMark(
                            x: .value("Month", entry.label),
                            y: .value("Value", entry.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.green.opacity(0.4), Color.teal.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Month", entry.label),
                            y: .value("Value", entry.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .teal],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        // Current month indicator
                        if entry.monthNumber == Calendar.current.component(.month, from: Date()) &&
                            selectedYear == Calendar.current.component(.year, from: Date()) {
                            PointMark(
                                x: .value("Month", entry.label),
                                y: .value("Value", entry.value)
                            )
                            .foregroundStyle(.green)
                            .symbolSize(40)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("$\(Int(v))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                                .foregroundStyle(.secondary.opacity(0.2))
                        }
                    }
                    .frame(height: 140)
                } else {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                            Text("No value extracted yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Month Pills

    private var monthPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // "All" pill
                monthPill(label: "All", monthNumber: nil)

                ForEach(1...12, id: \.self) { month in
                    let formatter = DateFormatter()
                    let _ = formatter.dateFormat = "MMM"
                    let date = Calendar.current.date(from: DateComponents(year: selectedYear, month: month))!
                    monthPill(label: formatter.string(from: date), monthNumber: month)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func monthPill(label: String, monthNumber: Int?) -> some View {
        let isSelected = selectedMonth == monthNumber

        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedMonth = monthNumber
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(
                                LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing)
                            )
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats Card

    @ViewBuilder
    private func statsCard(_ stats: UserStats) -> some View {
        AtmosphericCardView(
            gradientStart: .orange,
            gradientEnd: .yellow,
            gradientOpacity: 0.10
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Stats")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 16) {
                    // Lifetime saved
                    VStack(spacing: 4) {
                        OdometerText(
                            value: stats.lifetimeSaved,
                            font: .system(size: 20, weight: .bold, design: .monospaced),
                            color: AnyShapeStyle(.green)
                        )
                        Text("Lifetime")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Divider().frame(height: 30)

                    // Current streak
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                                .font(.system(size: 16))
                            Text("\(stats.currentStreak)")
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                        }
                        Text("Streak")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Divider().frame(height: 30)

                    // Achievements
                    VStack(spacing: 4) {
                        let earned = achievements.filter { $0.isUnlocked }.count
                        let total = achievements.count
                        Text("\(earned)/\(total)")
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                        Text("Badges")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                // Achievement badge icons (scrollable)
                let unlockedAchievements = achievements.filter { $0.isUnlocked }
                if !unlockedAchievements.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(unlockedAchievements) { achievement in
                                Image(systemName: achievement.icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(.yellow)
                                    .padding(8)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                        }
                    }
                }

                Button {
                    showAchievementsSheet = true
                } label: {
                    Text("View All Achievements")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Per-Card ROI Row

    @ViewBuilder
    private func cardROIRow(card: Card) -> some View {
        let startColor = Color(hex: card.gradientStartHex)
        let endColor = Color(hex: card.gradientEndHex)
        let claimed = card.credits.reduce(0.0) { $0 + PeriodEngine.totalClaimedThisYear(for: $1, year: selectedYear) }
        let roi = claimed - card.annualFee
        let isExpanded = expandedCards.contains(card.id)

        // Monthly data for sparkline
        let sparklineData: [Double] = (1...12).map { month in
            var total = 0.0
            let calendar = Calendar.current
            for credit in card.credits {
                for log in credit.periodLogs {
                    let logYear = calendar.component(.year, from: log.periodStart)
                    let logMonth = calendar.component(.month, from: log.periodStart)
                    if logYear == selectedYear && logMonth == month {
                        total += log.claimedAmount
                    }
                }
            }
            return total
        }

        AtmosphericCardView(
            gradientStart: startColor,
            gradientEnd: endColor,
            gradientOpacity: 0.12
        ) {
            VStack(alignment: .leading, spacing: 8) {
                // Gradient accent bar
                LinearGradient(colors: [startColor, endColor], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 3)
                    .clipShape(Capsule())

                Button {
                    expandHapticTrigger.toggle()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if expandedCards.contains(card.id) {
                            expandedCards.remove(card.id)
                        } else {
                            expandedCards.insert(card.id)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(card.name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("Fee: $\(Int(card.annualFee)) · Claimed: $\(String(format: "%.0f", claimed))")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }

                        // Inline sparkline
                        SparklineView(
                            data: sparklineData,
                            gradientStart: startColor,
                            gradientEnd: endColor
                        )

                        Spacer()

                        // ROI amount
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: roi >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(roi >= 0 ? .green : .red)
                                Text(roi >= 0 ? "+$\(String(format: "%.0f", roi))" : "-$\(String(format: "%.0f", abs(roi)))")
                                    .font(.system(size: max(15, min(20, abs(roi) / 50 + 15)), weight: .bold, design: .monospaced))
                                    .foregroundStyle(roi >= 0 ? .green : .red)
                            }
                            Text("Net ROI")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }

                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    }
                }
                .buttonStyle(.plain)

                // Expanded credit breakdown
                if isExpanded {
                    VStack(spacing: 4) {
                        ForEach(filteredCredits(for: card)) { credit in
                            NavigationLink {
                                CreditHistoryDetailView(credit: credit, card: card)
                            } label: {
                                creditSummaryRow(credit: credit, card: card)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func filteredCredits(for card: Card) -> [Credit] {
        card.credits.sorted { $0.name < $1.name }
    }

    @ViewBuilder
    private func creditSummaryRow(credit: Credit, card: Card) -> some View {
        let totalClaimed = PeriodEngine.totalClaimedThisYear(for: credit, year: selectedYear)
        let activePeriod = PeriodEngine.activePeriodLog(for: credit)

        HStack(spacing: 10) {
            ChunkyProgressRing(
                fraction: activePeriod?.fillFraction ?? 0,
                gradientStart: Color(hex: card.gradientStartHex),
                gradientEnd: Color(hex: card.gradientEndHex),
                strokeWidth: 4,
                size: 32,
                showLabel: false
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(credit.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Text("$\(String(format: "%.0f", totalClaimed)) claimed this year")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let period = activePeriod {
                GlassStatusPill(status: period.periodStatus)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

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
        .padding(.top, 60)
    }
}

// MARK: - Supporting Types

struct MonthlyROI: Identifiable {
    let id = UUID()
    let month: Date
    let label: String
    let value: Double
    let monthNumber: Int
}

// MARK: - Achievements Gallery Sheet

struct AchievementsGallerySheet: View {
    let achievements: [Achievement]

    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(achievements) { achievement in
                        AchievementBadgeView(achievement: achievement)
                    }
                }
                .padding(16)
            }
            .background(Color(hex: "#0A0A0F"))
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct AchievementBadgeView: View {
    let achievement: Achievement

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 64, height: 64)

                if achievement.isUnlocked {
                    // Full color with glow
                    Image(systemName: achievement.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(.yellow)
                        .shadow(color: .yellow.opacity(0.4), radius: 8)
                } else {
                    // Grayscale with lock
                    ZStack {
                        Image(systemName: achievement.icon)
                            .font(.system(size: 28))
                            .foregroundStyle(.gray.opacity(0.3))

                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .offset(x: 14, y: 14)
                    }
                }
            }

            Text(achievement.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(achievement.isUnlocked ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(achievement.requirement)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: [Card.self, Credit.self, PeriodLog.self, Achievement.self, UserStats.self], inMemory: true)
}
