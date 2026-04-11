import SwiftUI
import SwiftData

// MARK: - CardPaymentSettingsView

/// Modal sheet for configuring a card's payment due date and reminder preferences.
///
/// Presented from `CardSectionView`'s calendar button. Changes are saved locally via
/// SwiftData, rescheduled as a local notification, and pushed to Firestore in one action.
struct CardPaymentSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let card: Card

    // Mirror card state locally so the user can cancel without committing changes.
    @State private var reminderEnabled: Bool
    @State private var selectedDueDay: Int
    @State private var daysBefore: Int

    // Haptic trigger for the Save button confirmation.
    @State private var saveHapticTrigger = false

    private var startColor: Color { Color(hex: card.gradientStartHex) }
    private var endColor: Color { Color(hex: card.gradientEndHex) }

    init(card: Card) {
        self.card = card
        _reminderEnabled = State(initialValue: card.paymentReminderEnabled)
        _selectedDueDay  = State(initialValue: card.paymentDueDay ?? 1)
        _daysBefore      = State(initialValue: card.paymentReminderDaysBefore)
    }

    // MARK: - Computed helpers

    /// Human-readable date of the next scheduled reminder, shown as a preview.
    private var nextReminderDateString: String? {
        guard reminderEnabled else { return nil }
        let reminderDay = max(1, selectedDueDay - daysBefore)
        var components = Calendar.current.dateComponents([.year, .month], from: Date())
        components.day = reminderDay
        guard var date = Calendar.current.date(from: components) else { return nil }
        // Advance to next month if the calculated day has already passed this month.
        if date < Date() {
            date = Calendar.current.date(byAdding: .month, value: 1, to: date) ?? date
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    cardIdentityHeader
                    controlsSection
                    reminderPreview
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("Payment Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            // Liquid Glass sheet presentation.
            .presentationBackground(.ultraThinMaterial)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            // Success haptic fires as the save action commits.
            .sensoryFeedback(.success, trigger: saveHapticTrigger)
        }
    }

    // MARK: - Subviews

    /// Gradient card banner with name — visually anchors the modal to the card.
    private var cardIdentityHeader: some View {
        ZStack {
            LinearGradient(
                colors: [startColor, endColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 10) {
                Image(systemName: "creditcard.fill")
                    .font(.body.weight(.semibold))
                Text(card.name)
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// Liquid Glass control group: due day picker, reminder toggle, days-before stepper.
    private var controlsSection: some View {
        VStack(spacing: 0) {

            // — Statement Due Day —
            HStack {
                Label("Statement Due Day", systemImage: "calendar")
                    .font(.body)
                Spacer()
                Picker("Due Day", selection: $selectedDueDay) {
                    ForEach(1...31, id: \.self) { day in
                        Text(ordinalString(day)).tag(day)
                    }
                }
                .pickerStyle(.menu)
                .tint(startColor)
            }
            .padding()

            Divider().padding(.leading, 52)

            // — Payment Reminders Toggle —
            Toggle(isOn: $reminderEnabled.animation(.spring(response: 0.4, dampingFraction: 0.8))) {
                Label("Payment Reminders", systemImage: "bell.badge")
            }
            .padding()

            // — Days Before (conditionally revealed) —
            if reminderEnabled {
                Divider().padding(.leading, 52)

                HStack {
                    Label("Remind me", systemImage: "clock")
                        .font(.body)
                    Spacer()
                    // Stepper capped at 14 days — beyond that is impractical.
                    Stepper(
                        "\(daysBefore) day\(daysBefore == 1 ? "" : "s") before",
                        value: $daysBefore,
                        in: 1...14
                    )
                    .fixedSize()
                }
                .padding()
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Liquid Glass container — matches the card section aesthetic.
        .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }

    /// Small preview row showing the next computed reminder date.
    @ViewBuilder
    private var reminderPreview: some View {
        if let nextDate = nextReminderDateString {
            HStack(spacing: 6) {
                Image(systemName: "bell.fill")
                    .font(.caption)
                    .foregroundStyle(startColor)
                Text("Next reminder: \(nextDate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Actions

    /// Persists changes locally, reschedules the notification, and pushes to Firestore.
    private func save() {
        // 1. Apply local model changes.
        card.paymentDueDay              = selectedDueDay
        card.paymentReminderEnabled     = reminderEnabled
        card.paymentReminderDaysBefore  = daysBefore

        // 2. Commit to SwiftData.
        try? context.save()

        // 3. Reschedule the local push notification.
        NotificationManager.shared.schedulePaymentReminder(for: card)

        // 4. Push updated fields to Firestore for cross-device sync.
        Task {
            await FirestoreSyncService.shared.upload(card)
        }

        // 5. Trigger haptic and dismiss.
        saveHapticTrigger.toggle()
        dismiss()
    }

    // MARK: - Formatting

    /// Returns the ordinal string for a day number (e.g. 1 → "1st", 13 → "13th").
    private func ordinalString(_ day: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: day)) ?? "\(day)"
    }
}

// MARK: - Preview

#Preview {
    let card = Card(
        name: "Amex Gold",
        annualFee: 250,
        gradientStartHex: "#B76E79",
        gradientEndHex: "#C9A96E",
        paymentDueDay: 15,
        paymentReminderDaysBefore: 3,
        paymentReminderEnabled: true
    )
    return CardPaymentSettingsView(card: card)
        .modelContainer(for: [Card.self, Credit.self, PeriodLog.self], inMemory: true)
}
