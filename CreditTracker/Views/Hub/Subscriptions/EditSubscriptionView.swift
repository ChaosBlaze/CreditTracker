import SwiftUI
import SwiftData

struct EditSubscriptionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let subscription: Subscription

    @Query private var cards: [Card]

    // MARK: - Form State

    @State private var name = ""
    @State private var categoryRaw = SubscriptionCategory.other.rawValue
    @State private var costText = ""
    @State private var billingCycleRaw = BillingCycle.monthly.rawValue
    @State private var nextBillingDate = Date()
    @State private var isActive = true
    @State private var reminderEnabled = true
    @State private var reminderDays = 3
    @State private var selectedCardID = ""
    @State private var selectedCreditID = ""
    @State private var notes = ""
    @State private var showDeleteConfirmation = false

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
                    .onChange(of: selectedCardID) { _, newID in
                        // Clear credit when card changes, unless the selected credit still belongs to the new card
                        let newCard = cards.first { $0.id.uuidString == newID }
                        let creditStillValid = newCard?.credits.contains { $0.id.uuidString == selectedCreditID } ?? false
                        if !creditStillValid { selectedCreditID = "" }
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

                // ── Danger Zone ────────────────────────────────────────────────
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Subscription", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { loadFromSubscription() }
            .confirmationDialog(
                "Delete \"\(subscription.name)\"?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteAndDismiss() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove this subscription and its renewal reminder.")
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Load

    private func loadFromSubscription() {
        name             = subscription.name
        categoryRaw      = subscription.category
        costText         = String(format: "%.2f", subscription.cost)
        billingCycleRaw  = subscription.billingCycle
        nextBillingDate  = subscription.nextBillingDate
        isActive         = subscription.isActive
        reminderEnabled  = subscription.reminderEnabled
        reminderDays     = subscription.reminderDaysBefore
        selectedCardID   = subscription.linkedCardID
        selectedCreditID = subscription.linkedCreditID
        notes            = subscription.notes
    }

    // MARK: - Save

    private func save() {
        // Cancel existing reminder before mutating so it doesn't fire with stale data
        NotificationManager.shared.cancelSubscriptionReminder(for: subscription)

        subscription.name              = name.trimmingCharacters(in: .whitespaces)
        subscription.category          = categoryRaw
        subscription.cost              = Double(costText) ?? subscription.cost
        subscription.billingCycle      = billingCycleRaw
        subscription.nextBillingDate   = nextBillingDate
        subscription.isActive          = isActive
        subscription.reminderEnabled   = reminderEnabled
        subscription.reminderDaysBefore = reminderDays
        subscription.linkedCardID      = selectedCardID
        subscription.linkedCreditID    = selectedCreditID
        subscription.notes             = notes.trimmingCharacters(in: .whitespaces)

        try? context.save()
        NotificationManager.shared.scheduleSubscriptionReminder(for: subscription)
        Task { await FirestoreSyncService.shared.upload(subscription) }
        dismiss()
    }

    // MARK: - Delete

    private func deleteAndDismiss() {
        NotificationManager.shared.cancelSubscriptionReminder(for: subscription)
        let docID = subscription.syncID
        Task { await FirestoreSyncService.shared.deleteDocument(for: Subscription.self, id: docID) }
        context.delete(subscription)
        try? context.save()
        dismiss()
    }
}

#Preview {
    let sub = Subscription(name: "Netflix", category: .streaming, cost: 15.99, billingCycle: .monthly, nextBillingDate: Date())
    return EditSubscriptionView(subscription: sub)
        .modelContainer(for: [Subscription.self, Card.self, Credit.self], inMemory: true)
}
