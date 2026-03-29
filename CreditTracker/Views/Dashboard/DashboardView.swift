import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Card.sortOrder) private var cards: [Card]
    @Query private var statsArray: [UserStats]
    @State private var showAddCard = false

    private var stats: UserStats? { statsArray.first }

    // Aggregate calculations for hero card
    private var currentMonthClaimed: Double {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)

        return cards.flatMap { $0.credits }
            .filter { $0.timeframeType == .monthly }
            .compactMap { PeriodEngine.activePeriodLog(for: $0) }
            .filter {
                calendar.component(.month, from: $0.periodStart) == month &&
                calendar.component(.year, from: $0.periodStart) == year
            }
            .reduce(0) { $0 + $1.claimedAmount }
    }

    private var currentMonthTotal: Double {
        cards.flatMap { $0.credits }
            .filter { $0.timeframeType == .monthly }
            .reduce(0) { $0 + $1.totalValue }
    }

    private var claimedCount: Int {
        cards.flatMap { $0.credits }
            .compactMap { PeriodEngine.activePeriodLog(for: $0) }
            .filter { $0.periodStatus == .claimed }
            .count
    }

    private var pendingCount: Int {
        cards.flatMap { $0.credits }
            .compactMap { PeriodEngine.activePeriodLog(for: $0) }
            .filter { $0.periodStatus == .pending }
            .count
    }

    private var missedCount: Int {
        cards.flatMap { $0.credits }
            .compactMap { PeriodEngine.activePeriodLog(for: $0) }
            .filter { $0.periodStatus == .missed }
            .count
    }

    private var heroGradientColors: [Color] {
        let allColors = cards.prefix(4).flatMap { [Color(hex: $0.gradientStartHex), Color(hex: $0.gradientEndHex)] }
        return allColors.isEmpty ? [.purple, .blue] : Array(allColors)
    }

    private var monthProgress: Double {
        guard currentMonthTotal > 0 else { return 0 }
        return min(currentMonthClaimed / currentMonthTotal, 1.0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Hero "Savings Pulse" card
                    if !cards.isEmpty {
                        heroSavingsCard
                    }

                    // Card sections
                    if cards.isEmpty {
                        emptyState
                    } else {
                        ForEach(cards) { card in
                            CardSectionView(card: card)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(hex: "#0A0A0F"))
            .navigationTitle("Credits")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddCard = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .glassEffect(in: Circle())
                }
            }
            .task {
                evaluatePeriods()
            }
        }
        .sheet(isPresented: $showAddCard) {
            AddCardView()
        }
    }

    // MARK: - Hero Savings Card

    private var heroSavingsCard: some View {
        AtmosphericCardView(
            gradientStart: heroGradientColors.first ?? .purple,
            gradientEnd: heroGradientColors.last ?? .blue,
            gradientOpacity: 0.30
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Total Saved")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Streak badge (only if streak >= 2)
                    if let stats = stats, stats.currentStreak >= 2 {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                            Text("\(stats.currentStreak)-period streak")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                }

                // Hero dollar amount with gradient text
                GradientOdometerText(
                    value: currentMonthClaimed,
                    gradientColors: heroGradientColors,
                    font: .system(size: 34, weight: .bold, design: .monospaced)
                )

                // Aggregate progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.1))
                            .frame(height: 6)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: heroGradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * monthProgress, height: 6)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: monthProgress)
                    }
                }
                .frame(height: 6)

                // Status summary
                HStack(spacing: 16) {
                    statusBadge(count: claimedCount, label: "Claimed", color: .green)
                    statusBadge(count: pendingCount, label: "Pending", color: .orange)
                    if missedCount > 0 {
                        statusBadge(count: missedCount, label: "Missed", color: .red)
                    }
                    Spacer()
                }
            }
        }
        .parallaxEffect(magnitude: 5)
    }

    private func statusBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "creditcard.and.123")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Cards Yet")
                    .font(.title2.weight(.semibold))
                Text("Add a credit card to start tracking\nyour statement credits.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showAddCard = true
            } label: {
                Label("Add Your First Card", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .glassEffect(in: Capsule())
        }
        .padding(.top, 80)
    }

    // MARK: - Period Evaluation

    private func evaluatePeriods() {
        let allCredits = cards.flatMap { $0.credits }
        PeriodEngine.evaluateAndAdvancePeriods(for: allCredits, context: context)
        try? context.save()

        // Update streaks
        GamificationEngine.updateStreak(cards: Array(cards), context: context)

        Task { @MainActor in
            await NotificationManager.shared.checkStatus()
            NotificationManager.shared.rescheduleAll(credits: allCredits)
        }
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [Card.self, Credit.self, PeriodLog.self, Achievement.self, UserStats.self], inMemory: true)
}
