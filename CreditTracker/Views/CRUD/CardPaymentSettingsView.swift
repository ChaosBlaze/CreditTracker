import SwiftUI
import SwiftData

// MARK: - CardPaymentSettingsView

/// Modal sheet for configuring a card's payment due date, payment reminder, and
/// annual-fee renewal date.
///
/// Presented from `CardSectionView`'s calendar button. All changes are saved
/// locally via SwiftData, rescheduled as local notifications, and pushed to
/// Firestore in one action.
struct CardPaymentSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let card: Card

    // ── Payment settings ──────────────────────────────────────────────────────
    @State private var reminderEnabled: Bool
    @State private var selectedDueDay: Int
    @State private var daysBefore: Int

    // ── Annual fee date ───────────────────────────────────────────────────────
    /// Whether the user has set an annual fee renewal date.
    @State private var hasAnnualFeeDate: Bool
    /// The actual renewal date (only meaningful when `hasAnnualFeeDate == true`).
    @State private var annualFeeDate: Date
    /// Whether a 30-day advance notification should fire.
    @State private var annualFeeReminderEnabled: Bool

    // ── Haptic ────────────────────────────────────────────────────────────────
    @State private var saveHapticTrigger = false

    private var startColor: Color { Color(hex: card.gradientStartHex) }
    private var endColor:   Color { Color(hex: card.gradientEndHex) }

    init(card: Card) {
        self.card = card
        _reminderEnabled         = State(initialValue: card.paymentReminderEnabled)
        _selectedDueDay          = State(initialValue: card.paymentDueDay ?? 1)
        _daysBefore              = State(initialValue: card.paymentReminderDaysBefore)
        _hasAnnualFeeDate        = State(initialValue: card.annualFeeDate != nil)
        // Default to ~1 year from today when no date is stored yet.
        _annualFeeDate           = State(initialValue: card.annualFeeDate
            ?? Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date())
        _annualFeeReminderEnabled = State(initialValue: card.annualFeeReminderEnabled)
    }

    // MARK: - Computed helpers

    /// Human-readable date of the next scheduled payment reminder.
    private var nextPaymentReminderDateString: String? {
        guard reminderEnabled else { return nil }
        let reminderDay = max(1, selectedDueDay - daysBefore)
        var components = Calendar.current.dateComponents([.year, .month], from: Date())
        components.day = reminderDay
        guard var date = Calendar.current.date(from: components) else { return nil }
        if date < Date() {
            date = Calendar.current.date(byAdding: .month, value: 1, to: date) ?? date
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Human-readable date of the annual-fee advance notification (30 days before).
    private var annualFeeNotificationDateString: String? {
        guard hasAnnualFeeDate, annualFeeReminderEnabled else { return nil }
        guard let reminderDate = Calendar.current.date(byAdding: .day, value: -30, to: annualFeeDate),
              reminderDate > Date() else { return nil }
        return reminderDate.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    cardIdentityHeader
                    paymentControlsSection
                    paymentReminderPreview
                    annualFeeDateSection
                    annualFeeReminderPreview
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
            .presentationBackground(.ultraThinMaterial)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .sensoryFeedback(.success, trigger: saveHapticTrigger)
        }
    }

    // MARK: - Subviews

    /// Gradient card banner — visually anchors the modal to the card.
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

    /// Payment due day picker + reminder toggle + days-before stepper.
    private var paymentControlsSection: some View {
        VStack(spacing: 0) {
            // Statement Due Day
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

            // Payment Reminders Toggle
            Toggle(isOn: $reminderEnabled.animation(.spring(response: 0.4, dampingFraction: 0.8))) {
                Label("Payment Reminders", systemImage: "bell.badge")
            }
            .padding()

            // Days Before (conditionally revealed)
            if reminderEnabled {
                Divider().padding(.leading, 52)

                HStack {
                    Label("Remind me", systemImage: "clock")
                        .font(.body)
                    Spacer()
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
        .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }

    /// Small row showing next computed payment reminder date.
    @ViewBuilder
    private var paymentReminderPreview: some View {
        if let nextDate = nextPaymentReminderDateString {
            HStack(spacing: 6) {
                Image(systemName: "bell.fill")
                    .font(.caption)
                    .foregroundStyle(startColor)
                Text("Next payment reminder: \(nextDate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }

    // ── Annual Fee Date Section ────────────────────────────────────────────────

    /// Liquid Glass control group for the annual fee renewal date and its reminder.
    private var annualFeeDateSection: some View {
        VStack(spacing: 0) {
            // "Track Annual Fee Date" master toggle
            Toggle(
                isOn: $hasAnnualFeeDate.animation(.spring(response: 0.4, dampingFraction: 0.8))
            ) {
                Label("Track Annual Fee Date", systemImage: "calendar.badge.clock")
            }
            .padding()

            if hasAnnualFeeDate {
                Divider().padding(.leading, 52)

                // Date picker for the renewal date
                DatePicker(
                    "Annual Fee Date",
                    selection: $annualFeeDate,
                    displayedComponents: .date
                )
                .padding()
                .transition(.move(edge: .top).combined(with: .opacity))

                Divider().padding(.leading, 52)

                // 30-day advance reminder toggle
                Toggle(
                    isOn: $annualFeeReminderEnabled.animation(.spring(response: 0.4, dampingFraction: 0.8))
                ) {
                    Label("30-Day Reminder", systemImage: "bell.badge.exclamationmark")
                }
                .padding()
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }

    /// Small row showing when the annual-fee notification will fire.
    @ViewBuilder
    private var annualFeeReminderPreview: some View {
        if let notifDate = annualFeeNotificationDateString {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(startColor)
                Text("Annual fee reminder: \(notifDate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Actions

    private func save() {
        // ── Payment settings ──────────────────────────────────────────────────
        card.paymentDueDay             = selectedDueDay
        card.paymentReminderEnabled    = reminderEnabled
        card.paymentReminderDaysBefore = daysBefore

        // ── Annual fee date ───────────────────────────────────────────────────
        card.annualFeeDate             = hasAnnualFeeDate ? annualFeeDate : nil
        card.annualFeeReminderEnabled  = hasAnnualFeeDate && annualFeeReminderEnabled

        // Commit to SwiftData.
        try? context.save()

        // Reschedule payment reminder.
        NotificationManager.shared.schedulePaymentReminder(for: card)

        // Cancel any stale annual-fee reminder, then re-schedule if enabled.
        NotificationManager.shared.cancelAnnualFeeReminder(for: card)
        if card.annualFeeReminderEnabled {
            NotificationManager.shared.scheduleAnnualFeeReminder(for: card)
        }

        // Push all updated fields to Firestore for cross-device sync.
        Task { await FirestoreSyncService.shared.upload(card) }

        saveHapticTrigger.toggle()
        dismiss()
    }

    // MARK: - Formatting

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
