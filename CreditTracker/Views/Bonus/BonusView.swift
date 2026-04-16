import SwiftUI
import SwiftData

struct BonusView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BonusCard.dateOpened, order: .reverse) private var bonuses: [BonusCard]

    @State private var showAddBonus = false
    @State private var addBonusHapticTrigger = false

    // ── Completed row interaction ──────────────────────────────────────────────
    /// The completed bonus whose EditBonusView sheet is currently open.
    @State private var selectedCompletedBonus: BonusCard? = nil
    /// Drives .selection haptic on a single tap.
    @State private var completedTapTrigger = false
    /// Drives .impact haptic on long-press.
    @State private var completedLongPressTrigger = false

    private var active:    [BonusCard] { bonuses.filter { !$0.isCompleted } }
    private var completed: [BonusCard] { bonuses.filter {  $0.isCompleted } }

    var body: some View {
        NavigationStack {
            Group {
                if bonuses.isEmpty {
                    ScrollView {
                        emptyState
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if !active.isEmpty {
                                sectionHeader("Active", systemImage: "sparkles")
                                    .padding(.horizontal, 4)
                                    .padding(.top, 4)
                                ForEach(active) { bonus in
                                    BonusCardRowView(bonus: bonus)
                                }
                            }

                            if !completed.isEmpty {
                                sectionHeader("Completed", systemImage: "checkmark.seal.fill")
                                    .padding(.horizontal, 4)
                                    .padding(.top, active.isEmpty ? 4 : 8)

                                ForEach(completed) { bonus in
                                    completedBonusRow(bonus)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
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
            .sensoryFeedback(.impact(weight: .light),  trigger: addBonusHapticTrigger)
            // Haptics for completed-row interactions.
            .sensoryFeedback(.selection,               trigger: completedTapTrigger)
            .sensoryFeedback(.impact(weight: .medium), trigger: completedLongPressTrigger)
        }
        .sheet(isPresented: $showAddBonus) {
            AddBonusView()
        }
        // Single sheet binding driven by selectedCompletedBonus.
        // BonusCard is Identifiable via its UUID, so SwiftUI manages identity correctly.
        .sheet(item: $selectedCompletedBonus) { bonus in
            EditBonusView(bonus: bonus)
        }
    }

    // MARK: - Sub-views

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "gift.circle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Bonuses Yet")
                    .font(.title2.weight(.semibold))
                Text("Track sign-up bonuses and\nminimum spend requirements.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showAddBonus = true
            } label: {
                Label("Add Your First Bonus", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .glassEffect(in: Capsule())
        }
        .padding(.top, 80)
    }

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
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Completed Row
    //
    // Completed rows are visually muted (reduced opacity) but fully interactive:
    //   • Tap     → .selection haptic + open EditBonusView sheet.
    //   • Long press → .impact haptic  + open EditBonusView sheet.
    //
    // This lets users read miscNotes, review requirements, or un-complete a bonus
    // by toggling the "Bonus Earned" toggle inside EditBonusView.

    @ViewBuilder
    private func completedBonusRow(_ bonus: BonusCard) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(Color.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(bonus.cardName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                // Show account holder name when set — consistent with the active row.
                if !bonus.accountHolderName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                        Text(bonus.accountHolderName)
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }

                Text(bonus.bonusAmount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Earned")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green, in: Capsule())

                // Hint icon: signals the row is tappable without cluttering the layout.
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(0.80)
        // contentShape ensures the tap target covers the full card, not just the text.
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            completedTapTrigger.toggle()
            selectedCompletedBonus = bonus
        }
        .onLongPressGesture {
            completedLongPressTrigger.toggle()
            selectedCompletedBonus = bonus
        }
    }
}

#Preview {
    BonusView()
        .modelContainer(for: [BonusCard.self], inMemory: true)
}
