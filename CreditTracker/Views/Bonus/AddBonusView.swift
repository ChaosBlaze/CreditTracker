import SwiftUI
import SwiftData

struct AddBonusView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var cardName = ""
    @State private var bonusAmount = ""
    @State private var dateOpened = Date()

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
                Section("Card Details") {
                    TextField("Card Name", text: $cardName)
                    TextField("Bonus (e.g. 75,000 Points or $200)", text: $bonusAmount)
                    DatePicker("Date Opened", selection: $dateOpened, displayedComponents: .date)
                }

                Section("Requirements") {
                    // Purchases
                    Toggle("Minimum Spend", isOn: $requiresPurchases.animation(.spring(response: 0.3, dampingFraction: 0.8)))

                    if requiresPurchases {
                        HStack {
                            Text("Target")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("$")
                                .foregroundStyle(.secondary)
                            TextField("0", text: $purchaseTargetText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))

                        HStack {
                            Text("Spent so far")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("$")
                                .foregroundStyle(.secondary)
                            TextField("0", text: $currentPurchaseText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Direct deposit
                    Toggle("Direct Deposit", isOn: $requiresDirectDeposit.animation(.spring(response: 0.3, dampingFraction: 0.8)))

                    if requiresDirectDeposit {
                        HStack {
                            Text("Target")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("$")
                                .foregroundStyle(.secondary)
                            TextField("0", text: $directDepositTargetText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))

                        HStack {
                            Text("Deposited so far")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("$")
                                .foregroundStyle(.secondary)
                            TextField("0", text: $currentDDText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Other
                    Toggle("Other Requirement", isOn: $requiresOther.animation(.spring(response: 0.3, dampingFraction: 0.8)))

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

    private func save() {
        let bonus = BonusCard(
            cardName: cardName.trimmingCharacters(in: .whitespaces),
            bonusAmount: bonusAmount.trimmingCharacters(in: .whitespaces),
            dateOpened: dateOpened
        )

        bonus.requiresPurchases = requiresPurchases
        bonus.purchaseTarget = Double(purchaseTargetText) ?? 0
        bonus.currentPurchaseAmount = Double(currentPurchaseText) ?? 0

        bonus.requiresDirectDeposit = requiresDirectDeposit
        bonus.directDepositTarget = Double(directDepositTargetText) ?? 0
        bonus.currentDirectDepositAmount = Double(currentDDText) ?? 0

        bonus.requiresOther = requiresOther
        bonus.otherDescription = otherDescription

        context.insert(bonus)
        try? context.save()
        dismiss()
    }
}
