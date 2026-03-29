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
    @State private var deleteWarningTrigger = false
    @State private var showDeleteConfirmation = false

    private var startColor: Color { Color(hex: card.gradientStartHex) }
    private var endColor: Color { Color(hex: card.gradientEndHex) }

    // Mini dot status badge: current period claim total
    private var hasAnyClaimed: Bool {
        card.credits.contains { credit in
            guard let period = PeriodEngine.activePeriodLog(for: credit) else { return false }
            return period.claimedAmount > 0
        }
    }

    var body: some View {
        AtmosphericCardView(
            gradientStart: startColor,
            gradientEnd: endColor
        ) {
            VStack(alignment: .leading, spacing: 0) {
                // Gradient accent bar (top, full width)
                LinearGradient(
                    colors: [startColor, endColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 4)
                .clipShape(Capsule())
                .padding(.bottom, 12)

                // Card header
                Button {
                    expandHapticTrigger.toggle()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.name)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("$\(Int(card.annualFee))/yr · \(card.credits.count) credit\(card.credits.count == 1 ? "" : "s")")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Mini dot status badge
                        Capsule()
                            .fill(hasAnyClaimed ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 8, height: 8)

                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                            .animation(.spring(response: 0.3), value: isExpanded)
                    }
                }
                .buttonStyle(.plain)
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
                        context.delete(card)
                        try? context.save()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("All credits and history for this card will be permanently deleted.")
                }

                // Credits list
                if isExpanded {
                    if card.credits.isEmpty {
                        emptyCreditsState
                    } else {
                        VStack(spacing: 0) {
                            ForEach(card.credits.sorted { $0.name < $1.name }) { credit in
                                CreditRowView(credit: credit, card: card)

                                if credit.id != card.credits.sorted(by: { $0.name < $1.name }).last?.id {
                                    Divider()
                                        .padding(.leading, 56)
                                        .opacity(0.3)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddCredit) {
            AddCreditView(card: card)
        }
        .sheet(isPresented: $showEditCard) {
            EditCardView(card: card)
        }
    }

    private var emptyCreditsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.circle.dashed")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Add your first credit")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .contentShape(Rectangle())
        .onTapGesture {
            showAddCredit = true
        }
    }
}
