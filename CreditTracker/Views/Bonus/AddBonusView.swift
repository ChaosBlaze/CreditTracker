import SwiftUI
import SwiftData

struct AddBonusView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // ── Core Details ──────────────────────────────────────────────────────────
    @State private var cardName = ""
    @State private var bonusAmount = ""
    @State private var dateOpened = Date()

    // ── QoL Fields (Phase 1) ──────────────────────────────────────────────────
    /// Who opened the card. Helps distinguish between family members.
    @State private var accountHolderName = ""
    /// Free-form notepad for account numbers, referral links, etc.
    @State private var miscNotes = ""

    // ── Requirements ──────────────────────────────────────────────────────────
    @State private var requiresPurchases = false
    @State private var purchaseTargetText = ""
    @State private var currentPurchaseText = ""

    @State private var requiresDirectDeposit = false
    @State private var directDepositTargetText = ""
    @State private var currentDDText = ""

    @State private var requiresOther = false
    @State private var otherDescription = ""

    var canSave: Bool {
        !cardName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !bonusAmount.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Card Details ───────────────────────────────────────────────
                Section("Card Details") {
                    TextField("Card Name", text: $cardName)
                    TextField("Bonus (e.g. 75,000 Points or $200)", text: $bonusAmount)
                    DatePicker("Date Opened", selection: $dateOpened, displayedComponents: .date)
                }

                // ── Account Info (QoL) ─────────────────────────────────────────
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
                        .lineLimit(3...6)
                        .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Account Info")
                } footer: {
                    Text("Optional — helps distinguish cards across family members.")
                }

                // ── Requirements ───────────────────────────────────────────────
                Section("Requirements") {
                    // Minimum Spend
                    Toggle(
                        "Minimum Spend",
                        isOn: $requiresPurchases.animation(.spring(response: 0.3, dampingFraction: 0.8))
                    )

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
                            Text("Spent so far").foregroundStyle(.secondary)
                            Spacer()
                            Text("$").foregroundStyle(.secondary)
                            TextField("0", text: $currentPurchaseText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Direct Deposit
                    Toggle(
                        "Direct Deposit",
                        isOn: $requiresDirectDeposit.animation(.spring(response: 0.3, dampingFraction: 0.8))
                    )

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
                            Text("Deposited so far").foregroundStyle(.secondary)
                            Spacer()
                            Text("$").foregroundStyle(.secondary)
                            TextField("0", text: $currentDDText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Other
                    Toggle(
                        "Other Requirement",
                        isOn: $requiresOther.animation(.spring(response: 0.3, dampingFraction: 0.8))
                    )

                    if requiresOther {
                        TextField("Describe the requirement…", text: $otherDescription, axis: .vertical)
                            .lineLimit(2...4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .navigationTitle("New Bonus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Save

    private func save() {
        let bonus = BonusCard(
            cardName:    cardName.trimmingCharacters(in: .whitespaces),
            bonusAmount: bonusAmount.trimmingCharacters(in: .whitespaces),
            dateOpened:  dateOpened
        )

        // QoL fields
        bonus.accountHolderName = accountHolderName.trimmingCharacters(in: .whitespaces)
        bonus.miscNotes         = miscNotes

        // Requirements
        bonus.requiresPurchases       = requiresPurchases
        bonus.purchaseTarget          = Double(purchaseTargetText) ?? 0
        bonus.currentPurchaseAmount   = Double(currentPurchaseText) ?? 0

        bonus.requiresDirectDeposit       = requiresDirectDeposit
        bonus.directDepositTarget         = Double(directDepositTargetText) ?? 0
        bonus.currentDirectDepositAmount  = Double(currentDDText) ?? 0

        bonus.requiresOther    = requiresOther
        bonus.otherDescription = otherDescription

        // Persist locally first, then mirror to Firestore.
        context.insert(bonus)
        try? context.save()

        // Upload happens asynchronously so the sheet can dismiss immediately.
        Task { await FirestoreSyncService.shared.upload(bonus) }

        dismiss()
    }
}
