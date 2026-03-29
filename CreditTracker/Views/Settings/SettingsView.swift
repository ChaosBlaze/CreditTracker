import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Constants.hasSeededDataKey) private var hasSeededData = false
    @AppStorage(Constants.defaultReminderDaysKey) private var defaultReminderDays = Constants.defaultReminderDays
    @AppStorage(Constants.discordReminderEnabledKey) private var discordReminderEnabled = false
    @AppStorage(Constants.discordReminderHourKey) private var discordReminderHour = Constants.discordReminderDefaultHour
    @AppStorage(Constants.discordReminderMinuteKey) private var discordReminderMinute = Constants.discordReminderDefaultMinute

    @ObservedObject private var notificationManager = NotificationManager.shared
    @State private var showResetConfirmation = false
    @State private var showResetDone = false
    @State private var versionTapCount = 0
    @State private var showEasterEgg = false
    @State private var showDebugPanel = false
    @State private var testBellBounce = false
    @State private var pendingNotificationCount = 0
    @State private var periodLogCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    notificationCard
                    remindersCard
                    dataCard
                    aboutCard
                    developerSignature
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(hex: "#0A0A0F"))
            .navigationTitle("Settings")
            .task {
                await notificationManager.checkStatus()
            }
            .alert("Reset All Data?", isPresented: $showResetConfirmation) {
                Button("Reset", role: .destructive) {
                    resetData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all cards and credits, then re-seed the default data. This cannot be undone.")
            }
            .alert("Data Reset", isPresented: $showResetDone) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Default cards and credits have been restored.")
            }
            .overlay {
                if showEasterEgg {
                    MatrixRainView()
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Notification Card

    private var notificationCard: some View {
        AtmosphericCardView(
            gradientStart: .blue,
            gradientEnd: .purple,
            gradientOpacity: 0.08
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Notifications")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack {
                    Label("Permission Status", systemImage: "bell")
                        .font(.system(size: 15))
                    Spacer()
                    notificationStatusPill
                }

                Button {
                    testBellBounce = true
                    notificationManager.scheduleTestNotification()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        testBellBounce = false
                    }
                } label: {
                    HStack {
                        Image(systemName: "bell.badge.waveform")
                            .font(.system(size: 15))
                            .symbolEffect(.bounce, value: testBellBounce)
                        Text("Test Notification")
                            .font(.system(size: 15))
                    }
                    .foregroundStyle(.blue)
                }

                if notificationManager.authorizationStatus == .denied {
                    Button {
                        openSettings()
                    } label: {
                        HStack {
                            Image(systemName: "gear")
                            Text("Open System Settings")
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(.blue)
                    }
                } else if notificationManager.authorizationStatus == .notDetermined {
                    Button {
                        Task { await notificationManager.requestPermission() }
                    } label: {
                        HStack {
                            Image(systemName: "bell.badge")
                            Text("Request Permission")
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(.blue)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var notificationStatusPill: some View {
        switch notificationManager.authorizationStatus {
        case .authorized:
            GlassStatusPill(label: "Enabled", icon: "checkmark", tint: .green)
        case .denied:
            GlassStatusPill(label: "Denied", icon: "xmark", tint: .red)
        case .provisional:
            GlassStatusPill(label: "Provisional", icon: "exclamationmark.triangle", tint: .orange)
        default:
            GlassStatusPill(label: "Not Set", icon: "questionmark", tint: .gray)
        }
    }

    // MARK: - Reminders Card

    private var remindersCard: some View {
        AtmosphericCardView(
            gradientStart: .orange,
            gradientEnd: .yellow,
            gradientOpacity: 0.08
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reminders")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                // Default reminder days with glass stepper
                HStack {
                    Text("Default Reminder")
                        .font(.system(size: 15))

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            if defaultReminderDays > Constants.minReminderDays {
                                defaultReminderDays -= 1
                            }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .background(.ultraThinMaterial, in: Circle())

                        Text("\(defaultReminderDays)d")
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .contentTransition(.numericText())
                            .frame(width: 30)

                        Button {
                            if defaultReminderDays < Constants.maxReminderDays {
                                defaultReminderDays += 1
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .background(.ultraThinMaterial, in: Circle())
                    }
                }

                Toggle("Discord Redeem Reminder", isOn: $discordReminderEnabled)
                    .font(.system(size: 15))
                    .onChange(of: discordReminderEnabled) { _, newValue in
                        if newValue {
                            notificationManager.scheduleDiscordReminder()
                        } else {
                            notificationManager.cancelDiscordReminder()
                        }
                    }

                if discordReminderEnabled {
                    DatePicker(
                        "Reminder Time",
                        selection: discordReminderTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .font(.system(size: 15))
                }
            }
        }
    }

    private var discordReminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = discordReminderHour
                comps.minute = discordReminderMinute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                discordReminderHour = comps.hour ?? Constants.discordReminderDefaultHour
                discordReminderMinute = comps.minute ?? Constants.discordReminderDefaultMinute
                if discordReminderEnabled {
                    notificationManager.cancelDiscordReminder()
                    notificationManager.scheduleDiscordReminder()
                }
            }
        )
    }

    // MARK: - Data Card

    private var dataCard: some View {
        AtmosphericCardView(
            gradientStart: .red,
            gradientEnd: .orange,
            gradientOpacity: 0.06
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Data")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Button {
                    showResetConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to Default Data")
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - About Card

    private var aboutCard: some View {
        AtmosphericCardView(
            gradientStart: .gray,
            gradientEnd: .white,
            gradientOpacity: 0.05
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("About")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                aboutRow("App", value: "CreditTracker")
                aboutRow("iOS Target", value: "26.0+")
                aboutRow("Bundle ID", value: Constants.bundleID)

                // Version (tappable for easter egg)
                Button {
                    versionTapCount += 1
                    if versionTapCount >= 7 {
                        triggerEasterEgg()
                    }
                } label: {
                    HStack {
                        Text("Version")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("5.0")
                            .foregroundStyle(.primary)
                    }
                    .font(.system(size: 15))
                }
                .buttonStyle(.plain)

                // Debug panel (hidden until easter egg triggered)
                if showDebugPanel {
                    Divider().opacity(0.3)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Debug Panel")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.green)

                        debugRow("Pending Notifications", value: "\(pendingNotificationCount)")
                        debugRow("Period Logs", value: "\(periodLogCount)")

                        Button {
                            forceEvaluatePeriods()
                        } label: {
                            Text("Force Period Evaluation")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                    }
                    .task {
                        await loadDebugInfo()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func aboutRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
        }
        .font(.system(size: 15))
    }

    @ViewBuilder
    private func debugRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.green)
        }
        .font(.system(size: 13, design: .monospaced))
    }

    // MARK: - Developer Signature

    private var developerSignature: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * (1.0 / 12.0)
            let t = phase.truncatingRemainder(dividingBy: 1.0)

            let stops: [Gradient.Stop] = [
                .init(color: appleIntelligenceColor(base: 0.75, offset: t), location: 0.00),
                .init(color: appleIntelligenceColor(base: 0.88, offset: t), location: 0.33),
                .init(color: appleIntelligenceColor(base: 0.58, offset: t), location: 0.66),
                .init(color: appleIntelligenceColor(base: 0.08, offset: t), location: 1.00),
            ]

            Text("Built by Shekar")
                .font(.system(size: 14, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(
                    LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        }
    }

    private func appleIntelligenceColor(base: Double, offset: Double) -> Color {
        let hue = (base + offset).truncatingRemainder(dividingBy: 1.0)
        return Color(hue: hue, saturation: 0.68, brightness: 0.92)
    }

    // MARK: - Easter Egg

    private func triggerEasterEgg() {
        HapticEngine.shared.easterEgg()
        withAnimation(.easeInOut(duration: 0.3)) {
            showEasterEgg = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeInOut(duration: 0.5)) {
                showEasterEgg = false
            }
            showDebugPanel = true
            versionTapCount = 0
        }
    }

    private func loadDebugInfo() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        pendingNotificationCount = pending.count

        let logs = (try? context.fetch(FetchDescriptor<PeriodLog>())) ?? []
        periodLogCount = logs.count
    }

    private func forceEvaluatePeriods() {
        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        let allCredits = cards.flatMap { $0.credits }
        PeriodEngine.evaluateAndAdvancePeriods(for: allCredits, context: context)
        try? context.save()
        Task { await loadDebugInfo() }
    }

    // MARK: - Helpers

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func resetData() {
        let existing = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        for card in existing {
            context.delete(card)
        }
        try? context.save()

        hasSeededData = false
        SeedDataManager.seed(context: context)
        hasSeededData = true

        Task { @MainActor in
            let freshCards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
            let allCredits = freshCards.flatMap { $0.credits }
            NotificationManager.shared.rescheduleAll(credits: allCredits)
        }

        showResetDone = true
    }
}

// MARK: - Matrix Rain Easter Egg

struct MatrixRainView: View {
    @State private var columns: [MatrixColumn] = []

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let colWidth: CGFloat = 20
                let numCols = Int(size.width / colWidth)

                // Initialize columns if needed
                if columns.isEmpty || columns.count != numCols {
                    // Can't update state here, just draw with procedural animation
                }

                for col in 0..<numCols {
                    let seed = col * 7919 // prime for variation
                    let speed = 100 + Double(seed % 200)
                    let offset = Double(seed % 1000)
                    let yPos = ((elapsed + offset) * speed).truncatingRemainder(dividingBy: Double(size.height + 400)) - 200

                    // Draw trail of $ symbols
                    for row in 0..<15 {
                        let y = yPos - Double(row) * 22
                        guard y > -20 && y < Double(size.height + 20) else { continue }

                        let alpha = 1.0 - Double(row) / 15.0
                        let charHash = (col * 31 + row * 17 + Int(elapsed * 3)) % 4
                        let char = ["$", "¢", "€", "£"][charHash]

                        var textContext = context
                        textContext.opacity = alpha * 0.8

                        let text = Text(char)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)

                        textContext.draw(
                            text,
                            at: CGPoint(x: CGFloat(col) * colWidth + colWidth / 2, y: y)
                        )
                    }
                }
            }
        }
    }
}

struct MatrixColumn {
    var yOffset: Double
    var speed: Double
}

#Preview {
    SettingsView()
        .modelContainer(for: [Card.self, Credit.self, PeriodLog.self], inMemory: true)
}
