import SwiftUI
import SwiftData

struct BonusView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BonusCard.dateOpened, order: .reverse) private var bonuses: [BonusCard]
    @State private var showAddBonus = false
    @State private var addBonusHapticTrigger = false

    private var active: [BonusCard] { bonuses.filter { !$0.isCompleted } }
    private var completed: [BonusCard] { bonuses.filter { $0.isCompleted } }

    private var lifetimeBonusTotal: String {
        // Sum up completed bonus amounts (parse numeric portion)
        let total = completed.reduce(0.0) { sum, bonus in
            let numeric = bonus.bonusAmount.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            return sum + (Double(numeric) ?? 0)
        }
        if total > 0 {
            return "$\(Int(total))"
        }
        return "$0"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if bonuses.isEmpty {
                        emptyState
                    } else {
                        // Active bonuses
                        if !active.isEmpty {
                            sectionHeader("Active", systemImage: "sparkles", count: active.count)
                                .padding(.horizontal, 4)

                            ForEach(active) { bonus in
                                BonusCardRowView(bonus: bonus)
                            }
                        }

                        // Completed bonuses
                        if !completed.isEmpty {
                            sectionHeader("Completed", systemImage: "checkmark.seal.fill", count: completed.count)
                                .padding(.horizontal, 4)
                                .padding(.top, active.isEmpty ? 0 : 8)

                            // Lifetime bonus counter
                            HStack {
                                Image(systemName: "banknote.fill")
                                    .foregroundStyle(.green)
                                Text("\(lifetimeBonusTotal) earned from bonuses")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 4)

                            ForEach(completed) { bonus in
                                completedBonusRow(bonus)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(hex: "#0A0A0F"))
            .navigationTitle("Bonuses")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addBonusHapticTrigger.toggle()
                        showAddBonus = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .glassEffect(in: Circle())
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: addBonusHapticTrigger)
        }
        .sheet(isPresented: $showAddBonus) {
            AddBonusView()
        }
    }

    // MARK: - Sub-views

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Image(systemName: "gift.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                // Sparkle decorations
                Image(systemName: "sparkle")
                    .font(.system(size: 14))
                    .foregroundStyle(.yellow.opacity(0.6))
                    .offset(x: 30, y: -25)

                Image(systemName: "sparkle")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow.opacity(0.4))
                    .offset(x: -28, y: -20)

                Image(systemName: "sparkle")
                    .font(.system(size: 12))
                    .foregroundStyle(.yellow.opacity(0.5))
                    .offset(x: 20, y: 25)
            }

            VStack(spacing: 8) {
                Text("Track Your Sign-Up Bonuses")
                    .font(.title2.weight(.semibold))
                Text("Monitor spend requirements, direct deposits,\nand bonus milestones.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showAddBonus = true
            } label: {
                Label("Add Bonus", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .glassEffect(in: Capsule())
        }
        .padding(.top, 80)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, systemImage: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.3), in: Capsule())

            Spacer()
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func completedBonusRow(_ bonus: BonusCard) -> some View {
        let palette = BonusCardRowView.gradientPalette(for: bonus)

        AtmosphericCardView(
            gradientStart: palette.0,
            gradientEnd: palette.1,
            gradientOpacity: 0.10
        ) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text(bonus.cardName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(bonus.bonusAmount)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                GlassStatusPill(label: "Earned", icon: "checkmark", tint: .green)
            }
        }
        .opacity(0.8)
    }
}

#Preview {
    BonusView()
        .modelContainer(for: [BonusCard.self], inMemory: true)
}
