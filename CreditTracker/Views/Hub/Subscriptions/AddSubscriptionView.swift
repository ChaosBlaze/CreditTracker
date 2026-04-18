import SwiftUI
import SwiftData

struct AddSubscriptionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var cards: [Card]

    // MARK: - Form State

    @State private var name = ""
    @State private var categoryRaw = SubscriptionCategory.streaming.rawValue
    @State private var costText = ""
    @State private var billingCycleRaw = BillingCycle.monthly.rawValue
    @State private var nextBillingDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var isActive = true
    @State private var reminderEnabled = true
    @State private var reminderDays = 3
    @State private var selectedCardID = ""
    @State private var selectedCreditID = ""
    @State private var notes = ""

    // MARK: - Derived

    private var selectedCard: Card? {
        guard !selectedCardID.isEmpty else { return nil }
        return cards.first { $0.id.uuidString == selectedCardID }
    }

    private var creditsForSelectedCard: [Credit] {
        selectedCard?.credits ?? []
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (Double(costText) ?? 0) > 0
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // ── Details ────────────────────────────────────────────────────
                Section("Details") {
                    TextField("Subscription Name", text: $name)

                    Picker("Category", selection: $categoryRaw) {
                        ForEach(SubscriptionCategory.allCases, id: \.rawValue) { cat in
                            Label(cat.displayName, systemImage: cat.systemImage)
                                .tag(cat.rawValue)
                        }
                    }

                    HStack {
                        Text("Cost")
                        Spacer()
                        Text("$").foregroundStyle(.secondary)
                        TextField("0.00", text: $costText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }

                    Picker("Billing Cycle", selection: $billingCycleRaw) {
                        ForEach(BillingCycle.allCases, id: \.rawValue) { cycle in
                            Text(cycle.displayName).tag(cycle.rawValue)
                        }
                    }
                }

                // ── Billing ────────────────────────────────────────────────────
                Section("Billing") {
                    DatePicker("Next Billing Date", selection: $nextBillingDate, displayedComponents: .date)
                    Toggle("Active", isOn: $isActive)
                }

                // ── Linked Card ────────────────────────────────────────────────
                Section {
                    Picker("Card", selection: $selectedCardID) {
                        Text("None").tag("")
                        ForEach(cards) { card in
                            Text(card.name).tag(card.id.uuidString)
                        }
                    }
                    .onChange(of: selectedCardID) { _, _ in
                        // Clear credit selection when card changes
                        selectedCreditID = ""
                    }
                } header: {
                    Text("Linked Card")
                } footer: {
                    Text("Optionally link this subscription to a specific card.")
                }

                // ── Linked Credit ──────────────────────────────────────────────
                if !creditsForSelectedCard.isEmpty {
                    Section {
                        Picker("Covering Credit", selection: $selectedCreditID) {
                            Text("None").tag("")
                            ForEach(creditsForSelectedCard) { credit in
                                Text("\(credit.name) (\(credit.timeframeType.displayName))")
                                    .tag(credit.id.uuidString)
                            }
                        }
                    } header: {
                        Text("Linked Credit")
                    } footer: {
                        Text("Select a card credit that offsets the cost of this subscription.")
                    }
                }

                // ── Reminder ───────────────────────────────────────────────────
                Section("Reminder") {
                    Toggle("Renewal Reminder", isOn: $reminderEnabled.animation())

                    if reminderEnabled {
                        Stepper(
                            "\(reminderDays) day\(reminderDays == 1 ? "" : "s") before",
                            value: $reminderDays,
                            in: Constants.minReminderDays...Constants.maxReminderDays
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                // ── Notes ──────────────────────────────────────────────────────
                Section("Notes") {
                    TextField("Optional notes…", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("New Subscription")
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
        let cost = Double(costText) ?? 0
        let sub = Subscription(
            name: name.trimmingCharacters(in: .whitespaces),
            category: SubscriptionCategory(rawValue: categoryRaw) ?? .other,
            cost: cost,
            billingCycle: BillingCycle(rawValue: billingCycleRaw) ?? .monthly,
            nextBillingDate: nextBillingDate,
            isActive: isActive,
            reminderEnabled: reminderEnabled,
            reminderDaysBefore: reminderDays,
            linkedCardID: selectedCardID,
            linkedCreditID: selectedCreditID,
            notes: notes.trimmingCharacters(in: .whitespaces)
        )

        context.insert(sub)
        try? context.save()
        NotificationManager.shared.scheduleSubscriptionReminder(for: sub)
        Task { await FirestoreSyncService.shared.upload(sub) }
        dismiss()
    }
}

#Preview {
    AddSubscriptionView()
        .modelContainer(for: [Subscription.self, Card.self, Credit.self], inMemory: true)
}
