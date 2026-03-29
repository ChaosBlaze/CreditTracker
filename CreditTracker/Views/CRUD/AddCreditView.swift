import SwiftUI
import SwiftData

struct AddCreditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let card: Card

    @State private var name = ""
    @State private var totalValue = ""
    @State private var timeframe: TimeframeType = .monthly
    @State private var reminderDays = 5
    @State private var reminderEnabled = true
    @State private var saveHapticTrigger = false

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

                Section("Preview") {
                    HStack(spacing: 12) {
                        ProgressRingView(
                            fraction: 0,
                            startColor: Color(hex: card.gradientStartHex),
                            endColor: Color(hex: card.gradientEndHex),
                            lineWidth: 5,
                            size: 44
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name.isEmpty ? "Credit Name" : name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(name.isEmpty ? .tertiary : .primary)
                            Text("$\(totalValue.isEmpty ? "0" : totalValue) \(timeframe.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add Credit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveCredit()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (Double(totalValue) ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: saveHapticTrigger)
    }

    private func saveCredit() {
        let credit = Credit(
            name: name.trimmingCharacters(in: .whitespaces),
            totalValue: Double(totalValue) ?? 0,
            timeframe: timeframe,
            reminderDaysBefore: reminderDays,
            customReminderEnabled: reminderEnabled
        )
        credit.card = card
        card.credits.append(credit)
        context.insert(credit)

        // Create current period log
        PeriodEngine.ensureCurrentPeriodExists(for: credit, context: context)

        try? context.save()
        saveHapticTrigger.toggle()

        // Schedule notification
        if reminderEnabled, let activePeriod = PeriodEngine.activePeriodLog(for: credit) {
            NotificationManager.shared.scheduleReminder(for: credit, periodEnd: activePeriod.periodEnd)
        }

        dismiss()
    }
}
