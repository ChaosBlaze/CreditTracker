import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Card.sortOrder) private var cards: [Card]

    // MARK: - UI State

    @State private var showAddCard = false

    // MARK: - Edit Mode State

    /// Whether the dashboard is in card-reorder edit mode.
    @State private var isEditMode = false

    /// Local mutable snapshot of `cards` used during reordering.
    /// Seeded from `@Query` when edit mode begins; the new order is
    /// committed to SwiftData + Firestore when the user taps "Done".
    @State private var editableCards: [Card] = []

    // MARK: - Haptic Triggers

    @State private var editHapticTrigger = false
    @State private var doneHapticTrigger = false

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
                } else {
                    ScrollView {
                        // Use a regular (non-lazy) VStack in edit mode so SwiftUI can
                        // smoothly animate card reordering via spring transitions.
                        // LazyVStack is fine in normal mode for large lists.
                        VStack(spacing: 16) {
                            ForEach(isEditMode ? editableCards : cards) { card in
                                cardRow(card)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        // Propagate spring animation to all card-position changes
                        // that occur when editableCards is reordered by a drop.
                        .animation(
                            .spring(response: 0.35, dampingFraction: 0.8),
                            value: editableCards.map(\.id)
                        )
                    }
                }
            }
            .navigationTitle("Cards")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {

                    // ── Edit mode active ──────────────────────────────────────
                    if isEditMode {
                        Button {
                            doneHapticTrigger.toggle()
                            finishEditing()
                        } label: {
                            Text("Done")
                                .fontWeight(.semibold)
                                .padding(.horizontal, 4)
                        }
                        .glassEffect(in: Capsule())
                        .sensoryFeedback(.impact(weight: .medium), trigger: doneHapticTrigger)

                    // ── Normal mode ───────────────────────────────────────────
                    } else {
                        // Reorder button — only shown when there is more than one card.
                        if cards.count > 1 {
                            Button {
                                editHapticTrigger.toggle()
                                startEditing()
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                                    .fontWeight(.medium)
                            }
                            .glassEffect(in: Circle())
                            .sensoryFeedback(.impact(weight: .light), trigger: editHapticTrigger)
                        }

                        // Add card button.
                        Button {
                            showAddCard = true
                        } label: {
                            Image(systemName: "plus")
                                .fontWeight(.semibold)
                        }
                        .glassEffect(in: Circle())
                    }
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

    // MARK: - Card Row Builder

    /// Constructs a single card row with wiggle, drag, and drop behaviours applied.
    ///
    /// `.draggable` / `.dropDestination` are always attached but the drop handler
    /// returns `false` in non-edit mode, so reordering has no effect outside edit mode.
    /// The drag gesture (long-press + move) naturally coexists with the context menu
    /// (long-press stationary) that lives inside `CardSectionView`.
    private func cardRow(_ card: Card) -> some View {
        CardSectionView(card: card)
            // Phase 1 — Wiggle modifier: each card randomizes its own parameters.
            .wiggling(isActive: isEditMode)
            // Phase 3 — Drag source: payload is the card's UUID string (Transferable).
            .draggable(card.id.uuidString) {
                dragPreview(for: card)
            }
            // Phase 3 — Drop target: the dragged card lands at this card's position.
            .dropDestination(for: String.self) { droppedIDs, _ in
                guard isEditMode else { return false }
                return handleDrop(droppedIDs, onto: card)
            }
    }

    // MARK: - Drag Preview

    /// A lightweight, gradient-tinted card shape shown as the drag "ghost".
    ///
    /// Deliberately simpler than the full `CardSectionView` — it needs no
    /// SwiftData environment and renders without gesture recognisers.
    private func dragPreview(for card: Card) -> some View {
        let startColor = Color(hex: card.gradientStartHex)
        let endColor   = Color(hex: card.gradientEndHex)

        return HStack(spacing: 12) {
            // Accent strip matching the live card.
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(
                    colors: [startColor, endColor],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: 4, height: 32)

            Text(card.name)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            // Grip icon — visual cue that this is the card being moved.
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            LinearGradient(
                colors: [startColor.opacity(0.32), endColor.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1.5)
        }
        .shadow(color: startColor.opacity(0.3), radius: 14, y: 6)
        .opacity(0.88)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Edit Mode Lifecycle

    /// **Phase 2** — Enters edit mode: snapshots the current card order and triggers wiggle.
    private func startEditing() {
        // Take a snapshot of the current @Query order so reordering is decoupled from
        // SwiftData until the user commits by tapping "Done".
        editableCards = cards

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isEditMode = true
        }
    }

    /// **Phase 4** — Exits edit mode: persists changed sort orders and uploads to Firestore.
    private func finishEditing() {
        // Step 1: Update sortOrder values BEFORE toggling isEditMode so the
        // @Query(sort: \Card.sortOrder) result is already correct when SwiftUI
        // re-renders with `cards` as the source of truth — prevents a brief flash.
        var changedCards: [Card] = []
        for (newIndex, card) in editableCards.enumerated() {
            if card.sortOrder != newIndex {
                card.sortOrder = newIndex
                changedCards.append(card)
            }
        }

        // Step 2: NOW toggle — @Query sees correct sortOrder on first re-render.
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isEditMode = false
        }

        // Step 3: Persist to SwiftData then upload each changed card to Firestore.
        if !changedCards.isEmpty {
            try? context.save()
            Task {
                for card in changedCards {
                    await FirestoreSyncService.shared.upload(card)
                }
            }
        }

        // Clear local state — @Query will resume as the source of truth.
        editableCards = []
    }

    // MARK: - Drop Handler

    /// **Phase 3** — Moves the dragged card to the drop target's position in `editableCards`.
    ///
    /// - Returns: `true` if the reorder succeeded; `false` if any ID is invalid or the
    ///   source and destination indices are identical (no-op).
    @discardableResult
    private func handleDrop(_ droppedIDs: [String], onto targetCard: Card) -> Bool {
        // Validate: the payload must contain the dragged card's UUID string.
        guard
            let draggedIDString = droppedIDs.first,
            let draggedID       = UUID(uuidString: draggedIDString),
            let fromIndex       = editableCards.firstIndex(where: { $0.id == draggedID }),
            let toIndex         = editableCards.firstIndex(where: { $0.id == targetCard.id }),
            fromIndex != toIndex
        else {
            return false
        }

        // Perform the reorder inside a spring animation so sibling cards
        // slide smoothly to their new positions.
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            let card = editableCards.remove(at: fromIndex)
            // `toIndex` may have shifted by 1 after the remove when moving downward;
            // Array.insert handles this correctly — no clamping needed since
            // `toIndex` was derived from the pre-remove array and is always valid.
            editableCards.insert(card, at: min(toIndex, editableCards.count))
        }

        return true
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

        Task { @MainActor in
            await NotificationManager.shared.checkStatus()
            NotificationManager.shared.rescheduleAll(credits: allCredits)
        }
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
        .modelContainer(for: [Card.self, Credit.self, PeriodLog.self], inMemory: true)
}
