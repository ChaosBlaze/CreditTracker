import SwiftUI
import SwiftData

struct CreditRowView: View {
    @Environment(\.modelContext) private var context
    let credit: Credit
    let card: Card

    @State private var showLogModal   = false
    @State private var showEditCredit = false
    @State private var openHapticTrigger   = false
    @State private var editHapticTrigger   = false
    @State private var deleteHapticTrigger = false

    private var activePeriod: PeriodLog? { PeriodEngine.activePeriodLog(for: credit) }
    private var startColor: Color { Color(hex: card.gradientStartHex) }
    private var endColor:   Color { Color(hex: card.gradientEndHex) }

    var body: some View {
        HStack(spacing: 0) {

            // ── Primary tap area: opens the credit logging modal ───────────────
            Button {
                openHapticTrigger.toggle()
                showLogModal = true
            } label: {
                HStack(spacing: 12) {
                    // Progress ring
                    ProgressRingView(
                        fraction: activePeriod?.fillFraction ?? 0,
                        startColor: startColor,
                        endColor: endColor,
                        lineWidth: 5,
                        size: 46
                    )

                    // Credit name + period / status
                    VStack(alignment: .leading, spacing: 3) {
                        Text(credit.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        HStack(spacing: 6) {
                            if let period = activePeriod {
                                Text(period.periodLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                StatusPill(status: period.periodStatus)
                            }
                        }
                    }

                    Spacer()

                    // Dollar amounts + timeframe
                    VStack(alignment: .trailing, spacing: 2) {
                        if let period = activePeriod {
                            Text("$\(Int(period.claimedAmount)) / $\(Int(credit.totalValue))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            Text("$\(Int(credit.totalValue))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(credit.timeframeType.displayName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: openHapticTrigger)

            // ── Trailing ellipsis: Edit & Delete ──────────────────────────────
            //
            // Using a Menu instead of swipe actions because the credits list lives
            // inside a VStack (not a List), so .swipeActions() isn't available.
            // The ellipsis icon is always visible — discoverable without a long press.
            Menu {
                Button {
                    editHapticTrigger.toggle()
                    showEditCredit = true
                } label: {
                    Label("Edit Credit", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    deleteHapticTrigger.toggle()
                    deleteCredit()
                } label: {
                    Label("Delete Credit", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .sensoryFeedback(.impact(weight: .light), trigger: editHapticTrigger)
            .sensoryFeedback(.warning, trigger: deleteHapticTrigger)
        }
        .sheet(isPresented: $showLogModal) {
            CreditLoggingView(credit: credit, card: card)
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showEditCredit) {
            EditCreditView(credit: credit, card: card)
        }
    }

    // MARK: - Delete

    private func deleteCredit() {
        // Cancel any pending notification for this credit.
        NotificationManager.shared.cancelReminder(for: credit)

        // Delete from Firestore FIRST (period logs → credit document), then wipe
        // locally. The same repopulation race that affects card deletion applies
        // here: if we delete locally first, the next startListening() snapshot
        // delivery re-creates the credit from its still-live Firestore document.
        Task { @MainActor in
            await FirestoreSyncService.shared.deleteCreditCascading(credit)
            context.delete(credit)
            try? context.save()
        }
    }
}
