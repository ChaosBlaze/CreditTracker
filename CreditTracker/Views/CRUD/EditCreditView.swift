import SwiftUI
import SwiftData

struct EditCreditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let credit: Credit
    let card: Card

    @State private var name: String
    @State private var totalValue: String
    @State private var timeframe: TimeframeType
    @State private var reminderDays: Int
    @State private var reminderEnabled: Bool

    init(credit: Credit, card: Card) {
        self.credit = credit
        self.card = card
        _name = State(initialValue: credit.name)
        _totalValue = State(initialValue: String(Int(credit.totalValue)))
        _timeframe = State(initialValue: credit.timeframeType)
        _reminderDays = State(initialValue: credit.reminderDaysBefore)
        _reminderEnabled = State(initialValue: credit.customReminderEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Credit Details") {
                    TextField("Credit Name", text: $name)
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("Value per period", text: $totalValue)
                            .keyboardType(.decimalPad)
                    }
                    Picker("Timeframe", selection: $timeframe) {
                        ForEach(TimeframeType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                Section("Reminders") {
                    Toggle("Enable Reminder", isOn: $reminderEnabled)
                    if reminderEnabled {
                        Stepper(
                            "Remind \(reminderDays) day\(reminderDays == 1 ? "" : "s") before",
                            value: $reminderDays,
                            in: Constants.minReminderDays...Constants.maxReminderDays
                        )
                    }
                }

                Section {
                    Button(role: .destructive) {
                        NotificationManager.shared.cancelReminder(for: credit)
                        context.delete(credit)
                        try? context.save()
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Credit")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Credit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (Double(totalValue) ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func saveChanges() {
        credit.name = name.trimmingCharacters(in: .whitespaces)
        credit.totalValue = Double(totalValue) ?? 0
        credit.timeframe = timeframe.rawValue
        credit.reminderDaysBefore = reminderDays
        credit.customReminderEnabled = reminderEnabled

        // Reschedule notification
        NotificationManager.shared.cancelReminder(for: credit)
        if reminderEnabled, let activePeriod = PeriodEngine.activePeriodLog(for: credit) {
            if activePeriod.periodStatus == .pending || activePeriod.periodStatus == .partiallyClaimed {
                NotificationManager.shared.scheduleReminder(for: credit, periodEnd: activePeriod.periodEnd)
            }
        }

        try? context.save()
        dismiss()
    }
}
