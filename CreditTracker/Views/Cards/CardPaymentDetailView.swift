import SwiftUI
import SwiftData

struct CardPaymentDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let card: Card

    @State private var selectedDueDay: Int
    @State private var reminderDaysBefore: Int
    @State private var reminderEnabled: Bool
    @State private var showConfirmation = false
    @State private var nextReminderDate: Date? = nil

    private var startColor: Color { Color(hex: card.gradientStartHex) }
    private var endColor: Color { Color(hex: card.gradientEndHex) }

    init(card: Card) {
        self.card = card
        _selectedDueDay = State(initialValue: card.paymentDueDay ?? 0)
        _reminderDaysBefore = State(initialValue: card.paymentReminderDaysBefore)
        _reminderEnabled = State(initialValue: card.paymentReminderEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Card preview header
                Section {
                    cardPreviewHeader
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                // Due day picker
                Section("Payment Due Date") {
                    Picker("Due Day", selection: $selectedDueDay) {
                        Text("Not set").tag(0)
                        ForEach(1...31, id: \.self) { day in
                            Text(ordinal(day)).tag(day)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 150)
                }

                // Reminder settings (only shown when a due day is selected)
                if selectedDueDay > 0 {
                    Section("Reminder") {
                        Toggle("Enable Reminder", isOn: $reminderEnabled)
                            .sensoryFeedback(.selection, trigger: reminderEnabled)

                        if reminderEnabled {
                            Stepper(
                                "Remind \(reminderDaysBefore) day\(reminderDaysBefore == 1 ? "" : "s") before",
                                value: $reminderDaysBefore,
                                in: 1...14
                            )
                        }
                    }
                }

                // Save button
                Section {
                    Button(action: save) {
                        Text("Save")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundStyle(.white)
                    }
                    .listRowBackground(
                        LinearGradient(
                            colors: [startColor, endColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }
            .navigationTitle(card.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Reminder Scheduled", isPresented: $showConfirmation) {
                Button("OK") { dismiss() }
            } message: {
                if let date = nextReminderDate {
                    Text("Next reminder: \(date.formatted(date: .long, time: .omitted))")
                } else {
                    Text("Your payment reminder has been saved.")
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }

    // MARK: - Card preview

    private var cardPreviewHeader: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [startColor.opacity(0.65), endColor.opacity(0.50)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [startColor, endColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("$\(Int(card.annualFee))/yr annual fee")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedDueDay > 0 {
                        Label("Due on the \(ordinal(selectedDueDay))", systemImage: "calendar")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(16)
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: startColor.opacity(0.30), radius: 10, x: 0, y: 4)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func save() {
        card.paymentDueDay = selectedDueDay == 0 ? nil : selectedDueDay
        card.paymentReminderDaysBefore = reminderDaysBefore
        card.paymentReminderEnabled = reminderEnabled
        try? context.save()

        NotificationManager.shared.cancelPaymentReminder(for: card)

        if reminderEnabled && selectedDueDay > 0 {
            NotificationManager.shared.schedulePaymentReminder(for: card)
            nextReminderDate = computeNextReminderDate()
            showConfirmation = true
        } else {
            dismiss()
        }
    }

    private func computeNextReminderDate() -> Date? {
        guard selectedDueDay > 0 else { return nil }
        let reminderDay = max(1, selectedDueDay - reminderDaysBefore)
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.component(.day, from: now)
        let yearMonth = calendar.dateComponents([.year, .month], from: now)

        var comps = DateComponents()
        comps.day = reminderDay
        if reminderDay > today {
            comps.year = yearMonth.year
            comps.month = yearMonth.month
        } else {
            comps.year = yearMonth.year
            comps.month = (yearMonth.month ?? 1) + 1
        }

        return calendar.date(from: comps)
    }

    private func ordinal(_ day: Int) -> String {
        switch day {
        case 11, 12, 13: return "\(day)th"
        case let n where n % 10 == 1: return "\(day)st"
        case let n where n % 10 == 2: return "\(day)nd"
        case let n where n % 10 == 3: return "\(day)rd"
        default: return "\(day)th"
        }
    }
}
