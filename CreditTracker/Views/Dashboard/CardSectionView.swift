import SwiftUI
import SwiftData

struct CardSectionView: View {
    @Environment(\.modelContext) private var context
    let card: Card
    @State private var showAddCredit = false
    @State private var showEditCard = false
    @State private var isExpanded = true
    @State private var expandHapticTrigger = false
    @State private var openModalHapticTrigger = false
    @State private var paymentHapticTrigger = false
    @State private var deleteWarningTrigger = false
    @State private var showDeleteConfirmation = false
    @State private var showPaymentSettings = false

    private var startColor: Color { Color(hex: card.gradientStartHex) }
    private var endColor: Color { Color(hex: card.gradientEndHex) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Gradient tint layer — bleeds through the glass surface
            LinearGradient(
                colors: [startColor.opacity(0.35), endColor.opacity(0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

        VStack(alignment: .leading, spacing: 0) {
            // Card header — tapping most of the row toggles expand;
            // the calendar button opens payment settings without collapsing the section.
            HStack(spacing: 12) {
                // Card accent strip
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [startColor, endColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("$\(Int(card.annualFee))/yr · \(card.credits.count) credit\(card.credits.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Payment settings button — tinted when a due day is configured.
                Button {
                    paymentHapticTrigger.toggle()
                    showPaymentSettings = true
                } label: {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(card.paymentDueDay != nil ? startColor : .secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .light), trigger: paymentHapticTrigger)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .animation(.spring(response: 0.3), value: isExpanded)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // Make the full row (excluding the payment Button) tappable for expand/collapse.
            .contentShape(Rectangle())
            .onTapGesture {
                expandHapticTrigger.toggle()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }
            .sensoryFeedback(.selection, trigger: expandHapticTrigger)
            .contextMenu {
                Button {
                    openModalHapticTrigger.toggle()
                    showEditCard = true
                } label: {
                    Label("Edit Card", systemImage: "pencil")
                }
                Button {
                    openModalHapticTrigger.toggle()
                    showAddCredit = true
                } label: {
                    Label("Add Credit", systemImage: "plus")
                }
                Divider()
                Button(role: .destructive) {
                    deleteWarningTrigger.toggle()
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Card", systemImage: "trash")
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: openModalHapticTrigger)
            .sensoryFeedback(.warning, trigger: deleteWarningTrigger)
            .confirmationDialog("Delete \(card.name)?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Card", role: .destructive) {
                    Task { @MainActor in
                        // Delete from Firestore FIRST (period logs → credits → card).
                        // If we delete locally first, the snapshot listener re-delivers
                        // the Firestore documents on the next scene-active transition
                        // and re-creates the card in SwiftData — the repopulation bug.
                        await FirestoreSyncService.shared.deleteCardCascading(card)
                        // Now remove locally — SwiftData cascade deletes credits + period logs.
                        context.delete(card)
                        try? context.save()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All credits and history for this card will be permanently deleted.")
            }

            // Credits list
            if isExpanded {
                if card.credits.isEmpty {
                    HStack {
                        Spacer()
                        Button {
                            showAddCredit = true
                        } label: {
                            Label("Add a credit", systemImage: "plus.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(card.credits.sorted { $0.name < $1.name }) { credit in
                            CreditRowView(credit: credit, card: card)
                                .padding(.horizontal, 16)

                            if credit.id != card.credits.sorted { $0.name < $1.name }.last?.id {
                                Divider()
                                    .padding(.leading, 74)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        } // end ZStack
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: startColor.opacity(0.25), radius: 10, x: 0, y: 4)
        .sheet(isPresented: $showAddCredit) {
            AddCreditView(card: card)
        }
        .sheet(isPresented: $showEditCard) {
            EditCardView(card: card)
        }
        .sheet(isPresented: $showPaymentSettings) {
            CardPaymentSettingsView(card: card)
        }
    }
}
