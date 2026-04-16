import SwiftUI
import SwiftData

/// The Hub tab — a launchpad for all cross-cutting app features.
/// New features are added here as additional HubFeatureTile entries.
struct HubView: View {
    @Query private var bonuses: [BonusCard]
    @Query private var applications: [CardApplication]

    @AppStorage("plannerActivePlayer") private var activePlayer: String = "P1"

    private var activeBonusCount: Int {
        bonuses.filter { !$0.isCompleted }.count
    }

    private var bonusStat: String {
        switch activeBonusCount {
        case 0:  return "No active bonuses"
        case 1:  return "1 active bonus"
        default: return "\(activeBonusCount) active bonuses"
        }
    }

    private var plannerStat: String {
        let count = PlannerEligibilityEngine.chase524Count(
            player: activePlayer,
            applications: applications
        )
        let eligible = count < 5
        return eligible
            ? "\(activePlayer) · \(count)/5 · Eligible"
            : "\(activePlayer) · \(count)/5 · At limit"
    }

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader("Features", systemImage: "square.grid.2x2")
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    LazyVGrid(columns: columns, spacing: 16) {
                        // ── Bonuses — live ─────────────────────────────────────
                        NavigationLink(destination: BonusContentView()) {
                            HubFeatureTile(
                                title: "Bonuses",
                                systemImage: "sparkles",
                                description: "Track sign-up bonuses and minimum spend requirements.",
                                stat: bonusStat,
                                accentColor: .yellow,
                                isAvailable: true
                            )
                        }
                        .buttonStyle(.plain)

                        // ── Card Planner — live ────────────────────────────────
                        NavigationLink(destination: PlannerView()) {
                            HubFeatureTile(
                                title: "Card Planner",
                                systemImage: "chart.line.uptrend.xyaxis",
                                description: "Track 5/24, issuer velocity rules, and application history.",
                                stat: applications.isEmpty ? "No applications yet" : plannerStat,
                                accentColor: .purple,
                                isAvailable: true
                            )
                        }
                        .buttonStyle(.plain)

                        // ── Subscriptions — coming soon ────────────────────────
                        NavigationLink(destination: SubscriptionsPlaceholderView()) {
                            HubFeatureTile(
                                title: "Subscriptions",
                                systemImage: "repeat",
                                description: "Track recurring charges and link them to your cards.",
                                stat: nil,
                                accentColor: .blue,
                                isAvailable: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("Hub")
        }
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

#Preview {
    HubView()
        .modelContainer(for: [BonusCard.self, CardApplication.self], inMemory: true)
}
