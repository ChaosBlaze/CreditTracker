import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Card.sortOrder) private var cards: [Card]
    @State private var showAddCard = false

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    ScrollView {
                        emptyState
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(cards) { card in
                                CardSectionView(card: card)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
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

    private func evaluatePeriods() {
        let allCredits = cards.flatMap { $0.credits }
        PeriodEngine.evaluateAndAdvancePeriods(for: allCredits, context: context)
        try? context.save()

        // Reschedule notifications
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
