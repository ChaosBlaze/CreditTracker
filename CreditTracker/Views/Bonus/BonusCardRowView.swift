import SwiftUI
import SwiftData

// MARK: - BonusCardRowView

struct BonusCardRowView: View {
    @Environment(\.modelContext) private var context
    let bonus: BonusCard

    @State private var completeHapticTrigger = false
    @State private var showEditSheet = false

    // Gradient palette — cycles deterministically by card-name hash so the same
    // card always gets the same colours across reloads.
    private var cardGradient: (Color, Color) {
        let palettes: [(Color, Color)] = [
            (.purple, .indigo),
            (.orange, .pink),
            (.teal,   .cyan),
            (.green,  .mint),
            (.blue,   .purple),
            (.red,    .orange),
        ]
        let idx = abs(bonus.cardName.hashValue) % palettes.count
        return palettes[idx]
    }

    private var startColor: Color { cardGradient.0 }
    private var endColor:   Color { cardGradient.1 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Subtle gradient wash that tints the glass from behind.
            LinearGradient(
                colors: [startColor.opacity(0.22), endColor.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                // ── Header ────────────────────────────────────────────────────
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bonus.cardName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        // Account holder pill — only shown when the field is set.
                        // Frosted capsule keeps it subtle against the glass surface.
                        if !bonus.accountHolderName.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill")
                                    .font(.caption2)
                                Text(bonus.accountHolderName)
                                    .font(.caption2.weight(.medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                        }

                        Text(bonus.bonusAmount)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(startColor)

                        Text("Opened \(DateHelpers.shortDateString(bonus.dateOpened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if bonus.isCompleted {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(Color.green)
                    } else {
                        // Edit button for active cards.
                        Button {
                            showEditSheet = true
                        } label: {
                            Image(systemName: "pencil.circle")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // ── Requirements (active cards only) ──────────────────────────
                if !bonus.isCompleted {
                    Divider()
                    requirementsSection
                }
            }
            .padding(16)
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .sensoryFeedback(.success, trigger: completeHapticTrigger)
        .sheet(isPresented: $showEditSheet) {
            EditBonusView(bonus: bonus)
        }
    }

    // MARK: - Requirements Section

    @ViewBuilder
    private var requirementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if bonus.requiresPurchases    { purchaseProgressRow }
            if bonus.requiresDirectDeposit { directDepositRow   }
            if bonus.requiresOther         { otherRequirementRow }

            // "Mark complete" button — visible only when every requirement is satisfied.
            if bonus.allRequirementsMet {
                Button { markComplete() } label: {
                    Label("Mark Bonus Complete", systemImage: "star.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    private var purchaseProgressRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: bonus.currentPurchaseAmount >= bonus.purchaseTarget
                      ? "checkmark.circle.fill" : "cart")
                    .foregroundStyle(bonus.currentPurchaseAmount >= bonus.purchaseTarget ? Color.green : startColor)
                    .font(.caption)
                Text("Minimum Spend")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("$\(String(format: "%.0f", bonus.currentPurchaseAmount)) / $\(String(format: "%.0f", bonus.purchaseTarget))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LinearProgressBar(fraction: bonus.purchaseFraction, startColor: startColor, endColor: endColor)
        }
    }

    private var directDepositRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: bonus.currentDirectDepositAmount >= bonus.directDepositTarget
                      ? "checkmark.circle.fill" : "banknote")
                    .foregroundStyle(bonus.currentDirectDepositAmount >= bonus.directDepositTarget ? Color.green : startColor)
                    .font(.caption)
                Text("Direct Deposit")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("$\(String(format: "%.0f", bonus.currentDirectDepositAmount)) / $\(String(format: "%.0f", bonus.directDepositTarget))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LinearProgressBar(fraction: bonus.directDepositFraction, startColor: startColor, endColor: endColor)
        }
    }

    private var otherRequirementRow: some View {
        Button {
            bonus.isOtherCompleted.toggle()
            try? context.save()
            // Upload the toggled state to Firestore immediately.
            Task { await FirestoreSyncService.shared.upload(bonus) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: bonus.isOtherCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(bonus.isOtherCompleted ? Color.green : Color.secondary)
                    .font(.body)
                Text(bonus.otherDescription.isEmpty ? "Other Requirement" : bonus.otherDescription)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: bonus.isOtherCompleted)
    }

    private func markComplete() {
        bonus.isCompleted = true
        try? context.save()
        completeHapticTrigger.toggle()
        Task { await FirestoreSyncService.shared.upload(bonus) }
    }
}

// MARK: - Linear Progress Bar

struct LinearProgressBar: View {
    let fraction:   Double
    let startColor: Color
    let endColor:   Color
    var height: CGFloat = 6

    @State private var animated: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(startColor.opacity(0.15))
                    .frame(height: height)

                Capsule()
                    .fill(LinearGradient(
                        colors: [startColor, endColor],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: geo.size.width * animated, height: height)
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75)) { animated = fraction }
        }
        .onChange(of: fraction) { _, newValue in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { animated = newValue }
        }
    }
}

// MARK: - EditBonusView
//
// Full-featured editor used by:
//   • Active cards  — via the pencil button in BonusCardRowView.
//   • Completed cards — via tap / long-press in BonusView.
//
// Covers every editable field so either context gets the same rich experience.

struct EditBonusView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let bonus: BonusCard

    // ── All editable state ────────────────────────────────────────────────────
    @State private var cardName: String
    @State private var bonusAmount: String
    @State private var dateOpened: Date
    @State private var accountHolderName: String
    @State private var miscNotes: String

    @State private var requiresPurchases: Bool
    @State private var purchaseTargetText: String
    @State private var currentPurchaseText: String

    @State private var requiresDirectDeposit: Bool
    @State private var directDepositTargetText: String
    @State private var currentDDText: String

    @State private var requiresOther: Bool
    @State private var otherDescription: String
    @State private var isOtherCompleted: Bool

    /// Allows un-completing a bonus (e.g. if the user made a mistake).
    @State private var isCompleted: Bool

    // ── Init ──────────────────────────────────────────────────────────────────

    init(bonus: BonusCard) {
        self.bonus = bonus

        _cardName            = State(initialValue: bonus.cardName)
        _bonusAmount         = State(initialValue: bonus.bonusAmount)
        _dateOpened          = State(initialValue: bonus.dateOpened)
        _accountHolderName   = State(initialValue: bonus.accountHolderName)
        _miscNotes           = State(initialValue: bonus.miscNotes)

        _requiresPurchases   = State(initialValue: bonus.requiresPurchases)
        _purchaseTargetText  = State(initialValue: bonus.purchaseTarget > 0
            ? String(format: "%.2f", bonus.purchaseTarget) : "")
        _currentPurchaseText = State(initialValue: bonus.currentPurchaseAmount > 0
            ? String(format: "%.2f", bonus.currentPurchaseAmount) : "")

        _requiresDirectDeposit   = State(initialValue: bonus.requiresDirectDeposit)
        _directDepositTargetText = State(initialValue: bonus.directDepositTarget > 0
            ? String(format: "%.2f", bonus.directDepositTarget) : "")
        _currentDDText           = State(initialValue: bonus.currentDirectDepositAmount > 0
            ? String(format: "%.2f", bonus.currentDirectDepositAmount) : "")

        _requiresOther    = State(initialValue: bonus.requiresOther)
        _otherDescription = State(initialValue: bonus.otherDescription)
        _isOtherCompleted = State(initialValue: bonus.isOtherCompleted)
        _isCompleted      = State(initialValue: bonus.isCompleted)
    }

    // ── Body ──────────────────────────────────────────────────────────────────

    var body: some View {
        NavigationStack {
            Form {
                // ── Card Details ───────────────────────────────────────────────
                Section("Card Details") {
                    TextField("Card Name", text: $cardName)
                    TextField("Bonus (e.g. 75,000 Points or $200)", text: $bonusAmount)
                    DatePicker("Date Opened", selection: $dateOpened, displayedComponents: .date)
                }

                // ── Account Info ───────────────────────────────────────────────
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        TextField("Account Holder (e.g. Shekar, Wife)", text: $accountHolderName)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Notes", systemImage: "note.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(
                            "Account numbers, referral links, reminders…",
                            text: $miscNotes,
                            axis: .vertical
                        )
                        .lineLimit(3...8)
                        .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Account Info")
                }

                // ── Requirements ───────────────────────────────────────────────
                Section("Requirements") {
                    Toggle("Minimum Spend",
                           isOn: $requiresPurchases.animation(.spring(response: 0.3, dampingFraction: 0.8)))

                    if requiresPurchases {
                        HStack {
                            Text("Target").foregroundStyle(.secondary)
                            Spacer()
                            Text("$").foregroundStyle(.secondary)
                            TextField("0", text: $purchaseTargetText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))

                        HStack {
                            Text("Total Spent").foregroundStyle(.secondary)
                            Spacer()
                            Text("$").foregroundStyle(.secondary)
                            TextField("0", text: $currentPurchaseText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Toggle("Direct Deposit",
                           isOn: $requiresDirectDeposit.animation(.spring(response: 0.3, dampingFraction: 0.8)))

                    if requiresDirectDeposit {
                        HStack {
                            Text("Target").foregroundStyle(.secondary)
                            Spacer()
                            Text("$").foregroundStyle(.secondary)
                            TextField("0", text: $directDepositTargetText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))

                        HStack {
                            Text("Total Deposited").foregroundStyle(.secondary)
                            Spacer()
                            Text("$").foregroundStyle(.secondary)
                            TextField("0", text: $currentDDText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Toggle("Other Requirement",
                           isOn: $requiresOther.animation(.spring(response: 0.3, dampingFraction: 0.8)))

                    if requiresOther {
                        TextField("Describe the requirement…", text: $otherDescription, axis: .vertical)
                            .lineLimit(2...4)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                        Toggle("Requirement Done", isOn: $isOtherCompleted)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                // ── Status ─────────────────────────────────────────────────────
                Section {
                    Toggle("Bonus Earned", isOn: $isCompleted)
                } footer: {
                    Text("Toggle off to move this bonus back to Active.")
                }

                // ── Danger Zone ────────────────────────────────────────────────
                Section {
                    Button(role: .destructive) {
                        // Delete from Firestore first (while the relationship is still intact).
                        let docID = bonus.syncID
                        Task { await FirestoreSyncService.shared.deleteDocument(for: BonusCard.self, id: docID) }
                        context.delete(bonus)
                        try? context.save()
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Bonus")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Bonus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAll() }
                        .disabled(cardName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Save

    private func saveAll() {
        bonus.cardName          = cardName.trimmingCharacters(in: .whitespaces)
        bonus.bonusAmount       = bonusAmount.trimmingCharacters(in: .whitespaces)
        bonus.dateOpened        = dateOpened
        bonus.accountHolderName = accountHolderName.trimmingCharacters(in: .whitespaces)
        bonus.miscNotes         = miscNotes

        bonus.requiresPurchases       = requiresPurchases
        bonus.purchaseTarget          = Double(purchaseTargetText) ?? bonus.purchaseTarget
        bonus.currentPurchaseAmount   = Double(currentPurchaseText) ?? bonus.currentPurchaseAmount

        bonus.requiresDirectDeposit      = requiresDirectDeposit
        bonus.directDepositTarget        = Double(directDepositTargetText) ?? bonus.directDepositTarget
        bonus.currentDirectDepositAmount = Double(currentDDText) ?? bonus.currentDirectDepositAmount

        bonus.requiresOther    = requiresOther
        bonus.otherDescription = otherDescription
        bonus.isOtherCompleted = isOtherCompleted
        bonus.isCompleted      = isCompleted

        try? context.save()

        // Mirror the full updated state to Firestore so other devices pick it up.
        Task { await FirestoreSyncService.shared.upload(bonus) }

        dismiss()
    }
}
