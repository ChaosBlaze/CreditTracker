import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Card.sortOrder) private var cards: [Card]
    @State private var showAddCard = false
    @AppStorage("dashboardExpanded") private var expanded = false
    @State private var expandHapticTrigger = false

    // MARK: - Computed aggregates

    private var allCurrentLogs: [(Credit, PeriodLog?)] {
        cards.flatMap { card in
            card.credits.map { ($0, PeriodEngine.activePeriodLog(for: $0)) }
        }
    }

    private var totalAvailable: Double {
        allCurrentLogs.reduce(0) { $0 + $1.0.totalValue }
    }

    private var claimedThisMonth: Double {
        allCurrentLogs.reduce(0) { $0 + ($1.1?.claimedAmount ?? 0) }
    }

    private var unclaimedThisMonth: Double {
        max(0, totalAvailable - claimedThisMonth)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    ScrollView {
                        emptyState
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .background(CT.background.ignoresSafeArea())
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            HeroCardView(
                                unclaimedAmount: unclaimedThisMonth,
                                totalAvailable: totalAvailable,
                                claimedAmount: claimedThisMonth
                            )

                            ExpiresSoonSection(cards: cards)

                            allCardsSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background(CT.background.ignoresSafeArea())
                }
            }
            .navigationTitle("Cards")
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

    // MARK: - All Cards Section

    private var allCardsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("ALL CARDS")
                    .font(.ctSectionLabel)
                    .tracking(1.5)
                    .foregroundStyle(CT.ink3)

                Spacer()

                ExpandChip(expanded: $expanded)
            }

            if expanded {
                VStack(spacing: 12) {
                    ForEach(cards) { card in
                        CardExpandedBlock(card: card)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                VStack(spacing: 4) {
                    ForEach(cards) { card in
                        CollapsedCardRow(card: card)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: expanded)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "creditcard.and.123")
                .font(.system(size: 56))
                .foregroundStyle(CT.ink3)

            VStack(spacing: 8) {
                Text("No Cards Yet")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(CT.ink)
                Text("Add a credit card to start tracking\nyour statement credits.")
                    .font(.subheadline)
                    .foregroundStyle(CT.ink2)
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

        Task { @MainActor in
            await NotificationManager.shared.checkStatus()
            NotificationManager.shared.rescheduleAll(credits: allCredits)
        }
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [Card.self, Credit.self, PeriodLog.self], inMemory: true)
}
