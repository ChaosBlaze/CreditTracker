import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Constants.hasSeededDataKey)        private var hasSeededData      = false
    @AppStorage(Constants.defaultReminderDaysKey)  private var defaultReminderDays = Constants.defaultReminderDays

    // FamilySettings singleton — queried as an array, accessed via .first.
    // The .task modifier ensures the singleton is created before user interaction.
    @Query private var settingsArray: [FamilySettings]

    @State private var notificationManager = NotificationManager.shared
    @State private var syncService         = FirestoreSyncService.shared
    @State private var showResetConfirmation = false
    @State private var showResetDone         = false
    @State private var showJoinFamilySheet   = false
    @State private var isSendingTestPush     = false
    @State private var showTestPushResult    = false
    @State private var testPushSuccess       = false

    // MARK: - FamilySettings Accessor

    /// Returns the live FamilySettings singleton, or nil while the DB is loading.
    /// `ensureFamilySettingsSingleton()` in `.task {}` guarantees it exists quickly.
    private var familySettings: FamilySettings? { settingsArray.first }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                notificationSection
                defaultsSection
                syncSection
                familySyncSection
                dataSection
                aboutSection
                debugSection
                developerSignatureSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .task {
                await notificationManager.checkStatus()
                ensureFamilySettingsSingleton()
            }
            .alert("Reset All Data?", isPresented: $showResetConfirmation) {
                Button("Reset", role: .destructive) { resetData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all cards and credits, then re-seed the default data. This cannot be undone.")
            }
            .alert("Data Reset", isPresented: $showResetDone) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Default cards and credits have been restored.")
            }
        }
    }

    // MARK: - Sections

    private var notificationSection: some View {
        Section("Notifications") {
            HStack {
                Label("Permission Status", systemImage: "bell")
                Spacer()
                statusBadge
            }

            Button {
                notificationManager.scheduleTestNotification()
            } label: {
                Label("Test Notification", systemImage: "bell.badge.waveform")
                    .foregroundStyle(.blue)
            }

            if notificationManager.authorizationStatus == .denied {
                Button {
                    openSettings()
                } label: {
                    Label("Open System Settings", systemImage: "gear")
                        .foregroundStyle(.blue)
                }
            } else if notificationManager.authorizationStatus == .notDetermined {
                Button {
                    Task { await notificationManager.requestPermission() }
                } label: {
                    Label("Request Permission", systemImage: "bell.badge")
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    private var defaultsSection: some View {
        Section("Reminders") {
            Stepper(
                "Default Reminder: \(defaultReminderDays) day\(defaultReminderDays == 1 ? "" : "s") before",
                value: $defaultReminderDays,
                in: Constants.minReminderDays...Constants.maxReminderDays
            )

            // Discord reminder toggle — reads/writes FamilySettings and syncs to Firestore.
            Toggle("Discord Redeem Reminder", isOn: discordEnabledBinding)

            // Time picker — only shown when the reminder is active.
            if familySettings?.discordReminderEnabled == true {
                DatePicker(
                    "Reminder Time",
                    selection: discordReminderTimeBinding,
                    displayedComponents: .hourAndMinute
                )
            }

            // Test button — sends a silent push to all OTHER family devices so you can
            // verify background delivery works without changing the reminder time.
            Button {
                guard !isSendingTestPush else { return }
                isSendingTestPush = true
                let hour    = familySettings?.discordReminderHour   ?? Constants.discordReminderDefaultHour
                let minute  = familySettings?.discordReminderMinute ?? Constants.discordReminderDefaultMinute
                let enabled = familySettings?.discordReminderEnabled ?? false
                Task {
                    testPushSuccess   = await DiscordFamilyPushService.shared.sendTestPush(
                        hour: hour, minute: minute, enabled: enabled
                    )
                    isSendingTestPush = false
                    showTestPushResult = true
                }
            } label: {
                if isSendingTestPush {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Sending Test Push…").foregroundStyle(.secondary)
                    }
                } else {
                    Label("Send Test Push to Family", systemImage: "paperplane.fill")
                        .foregroundStyle(.blue)
                }
            }
            .disabled(isSendingTestPush)
            .alert("Test Push", isPresented: $showTestPushResult) {
                Button("OK", role: .cancel) {}
            } message: {
                if testPushSuccess {
                    Text("Test push sent to other family devices. Their apps should receive a silent notification and reschedule the Discord reminder — even if the app is in the background.")
                } else {
                    Text("Cloud Function unreachable. Make sure 'sendFamilyDiscordPush' is deployed in your Firebase project (see CloudFunctions/index.js).")
                }
            }
        }
    }

    private var syncSection: some View {
        Section("Firestore Sync") {
            HStack {
                Label("Status", systemImage: "arrow.triangle.2.circlepath.icloud")
                Spacer()
                syncStateBadge
            }
            HStack {
                Label("Last Synced", systemImage: "clock")
                Spacer()
                if let date = syncService.lastSyncedAt {
                    Text(date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Never")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Device ID", value: String(syncService.userID.prefix(8)) + "…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var syncStateBadge: some View {
        switch syncService.syncState {
        case .idle:
            Text(syncService.lastSyncedAt == nil ? "Not configured" : "Connected")
                .font(.caption.weight(.medium))
                .foregroundStyle(syncService.lastSyncedAt == nil ? Color.secondary : Color.green)
        case .syncing:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.7)
                Text("Syncing")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
            }
        case .error(let msg):
            Text("Error")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red, in: Capsule())
                .help(msg)
        }
    }

    private var familySyncSection: some View {
        Section("Family Sync") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Shared Family ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(syncService.userID)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)

                    Spacer()

                    Button {
                        UIPasteboard.general.string = syncService.userID
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Button("Join Existing Family") {
                showJoinFamilySheet = true
            }
        }
        .sheet(isPresented: $showJoinFamilySheet) {
            JoinFamilySheet(modelContext: context)
        }
    }

    private var dataSection: some View {
        Section("Data") {
            Button {
                showResetConfirmation = true
            } label: {
                Label("Reset to Default Data", systemImage: "arrow.counterclockwise")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App",        value: "CreditTracker")
            LabeledContent("Version",    value: "4.0")
            LabeledContent("iOS Target", value: "26.0+")
            LabeledContent("Bundle ID",  value: Constants.bundleID)
                .font(.caption)
        }
    }

    private var debugSection: some View {
        Section("Debug (Temporary)") {
            Button("Force Upload All Data") {
                Task { @MainActor in
                    let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
                    for card in cards { await syncService.upload(card) }

                    let credits = (try? context.fetch(FetchDescriptor<Credit>())) ?? []
                    for credit in credits { await syncService.upload(credit) }

                    let logs = (try? context.fetch(FetchDescriptor<PeriodLog>())) ?? []
                    for log in logs { await syncService.upload(log) }

                    // Also upload FamilySettings so the cloud is current.
                    if let settings = familySettings {
                        await syncService.upload(settings)
                    }

                    print("Finished uploading \(cards.count) cards, \(credits.count) credits, and \(logs.count) logs.")
                }
            }
        }
    }

    private var developerSignatureSection: some View {
        Section {
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
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .tracking(0.4)
                    .foregroundStyle(
                        LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            }
        }
        .listRowBackground(Color.clear)
    }

    private func appleIntelligenceColor(base: Double, offset: Double) -> Color {
        let hue = (base + offset).truncatingRemainder(dividingBy: 1.0)
        return Color(hue: hue, saturation: 0.68, brightness: 0.92)
    }

    // MARK: - FamilySettings Bindings

    /// Toggle binding for Discord Redeem Reminder enabled state.
    ///
    /// On change: persists to SwiftData, mirrors to UserDefaults (for rescheduleAll
    /// backward compat), reschedules notification, and pushes to Firestore.
    private var discordEnabledBinding: Binding<Bool> {
        Binding(
            get: { familySettings?.discordReminderEnabled ?? false },
            set: { newValue in
                guard let settings = familySettings else { return }
                settings.discordReminderEnabled = newValue
                // Stamp our FCM token so other devices know who made this change.
                settings.lastModifiedByToken = UserDefaults.standard.string(forKey: Constants.fcmTokenKey) ?? ""
                // Mirror to UserDefaults so rescheduleAll() stays in sync.
                UserDefaults.standard.set(newValue, forKey: Constants.discordReminderEnabledKey)
                try? context.save()
                if newValue {
                    notificationManager.scheduleDiscordReminder(
                        hour:   settings.discordReminderHour,
                        minute: settings.discordReminderMinute
                    )
                } else {
                    notificationManager.cancelDiscordReminder()
                }
                // Upload to Firestore first, then push to background family devices.
                let hour    = settings.discordReminderHour
                let minute  = settings.discordReminderMinute
                Task {
                    await FirestoreSyncService.shared.upload(settings)
                    await DiscordFamilyPushService.shared.sendDiscordUpdate(
                        hour: hour, minute: minute, enabled: newValue
                    )
                }
            }
        )
    }

    /// DatePicker binding mapping a `Date` (time only) to FamilySettings hour + minute.
    ///
    /// On change: persists to SwiftData, mirrors to UserDefaults, reschedules
    /// notification, and pushes to Firestore.
    private var discordReminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                let hour   = familySettings?.discordReminderHour   ?? Constants.discordReminderDefaultHour
                let minute = familySettings?.discordReminderMinute ?? Constants.discordReminderDefaultMinute
                var comps  = DateComponents()
                comps.hour   = hour
                comps.minute = minute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                guard let settings = familySettings else { return }
                let comps     = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                let newHour   = comps.hour   ?? Constants.discordReminderDefaultHour
                let newMinute = comps.minute ?? Constants.discordReminderDefaultMinute

                settings.discordReminderHour     = newHour
                settings.discordReminderMinute   = newMinute
                // Stamp FCM token so other devices can identify the change author.
                settings.lastModifiedByToken = UserDefaults.standard.string(forKey: Constants.fcmTokenKey) ?? ""
                // Mirror to UserDefaults for rescheduleAll() backward compat.
                UserDefaults.standard.set(newHour,   forKey: Constants.discordReminderHourKey)
                UserDefaults.standard.set(newMinute, forKey: Constants.discordReminderMinuteKey)
                try? context.save()
                let reminderEnabled = settings.discordReminderEnabled
                if reminderEnabled {
                    notificationManager.cancelDiscordReminder()
                    notificationManager.scheduleDiscordReminder(hour: newHour, minute: newMinute)
                }
                // Upload to Firestore first, then push to background family devices.
                Task {
                    await FirestoreSyncService.shared.upload(settings)
                    await DiscordFamilyPushService.shared.sendDiscordUpdate(
                        hour: newHour, minute: newMinute, enabled: reminderEnabled
                    )
                }
            }
        )
    }

    // MARK: - FamilySettings Bootstrap

    /// Creates the FamilySettings singleton on first launch, migrating values from the
    /// legacy @AppStorage keys so existing users keep their configured reminder time.
    private func ensureFamilySettingsSingleton() {
        guard settingsArray.isEmpty else { return }
        let settings = FamilySettings.migratingFromAppStorage()
        context.insert(settings)
        try? context.save()
        // Upload immediately so other family devices receive the initial document.
        Task { await FirestoreSyncService.shared.upload(settings) }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var statusBadge: some View {
        switch notificationManager.authorizationStatus {
        case .authorized:
            Text("Enabled")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green, in: Capsule())
        case .denied:
            Text("Denied")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red, in: Capsule())
        case .provisional:
            Text("Provisional")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange, in: Capsule())
        default:
            Text("Not Requested")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func resetData() {
        Task { @MainActor in
            let sync = FirestoreSyncService.shared

            let logsToRemove    = (try? context.fetch(FetchDescriptor<PeriodLog>())) ?? []
            let creditsToRemove = (try? context.fetch(FetchDescriptor<Credit>())) ?? []
            let cardsToRemove   = (try? context.fetch(FetchDescriptor<Card>())) ?? []

            for log    in logsToRemove    { await sync.deleteDocument(for: PeriodLog.self, id: log.syncID) }
            for credit in creditsToRemove { await sync.deleteDocument(for: Credit.self,    id: credit.syncID) }
            for card   in cardsToRemove   { await sync.deleteDocument(for: Card.self,      id: card.syncID) }

            for card in cardsToRemove { context.delete(card) }
            try? context.save()

            hasSeededData = false
            await SeedDataManager.seed(context: context)
            hasSeededData = true

            let freshCards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
            let allCredits = freshCards.flatMap { $0.credits }
            NotificationManager.shared.rescheduleAll(credits: allCredits)

            showResetDone = true
        }
    }
}

// MARK: - JoinFamilySheet

struct JoinFamilySheet: View {
    @Environment(\.dismiss) private var dismiss
    var modelContext: ModelContext

    @State private var inputID: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("Enter Family ID"),
                    footer: Text("Joining a family will wipe your current local cards and replace them with the shared family data. This cannot be undone.")
                ) {
                    TextField("Paste Family ID Here", text: $inputID)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Button(role: .destructive) {
                    joinFamily()
                } label: {
                    Text("Wipe Data & Join Family")
                        .frame(maxWidth: .infinity)
                }
                .disabled(inputID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("Join Family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func joinFamily() {
        let id = inputID.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try FirestoreSyncService.shared.joinFamilySync(id: id, context: modelContext)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .modelContainer(for: [Card.self, Credit.self, PeriodLog.self, FamilySettings.self], inMemory: true)
}
