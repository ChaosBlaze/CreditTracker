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

    @State private var notificationManager = NotificationManager.shared
    @State private var syncService = FirestoreSyncService.shared
    @State private var showResetConfirmation = false
    @State private var showResetDone = false
    @State private var showJoinFamilySheet = false

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
                    Task {
                        await notificationManager.requestPermission()
                    }
                } label: {
                    Label("Request Permission", systemImage: "bell.badge")
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    /// A `Date` binding that maps to/from the stored hour and minute integers.
    /// Only the time components matter; the date portion is today and is ignored.
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
                // Reschedule with the new time if the reminder is currently active
                if discordReminderEnabled {
                    notificationManager.cancelDiscordReminder()
                    notificationManager.scheduleDiscordReminder()
                }
            }
        )
    }

    private var defaultsSection: some View {
        Section("Reminders") {
            Stepper(
                "Default Reminder: \(defaultReminderDays) day\(defaultReminderDays == 1 ? "" : "s") before",
                value: $defaultReminderDays,
                in: Constants.minReminderDays...Constants.maxReminderDays
            )
            Toggle("Discord Redeem Reminder", isOn: $discordReminderEnabled)
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
            LabeledContent("App", value: "CreditTracker")
            LabeledContent("Version", value: "4.0")
            LabeledContent("iOS Target", value: "26.0+")
            LabeledContent("Bundle ID", value: Constants.bundleID)
                .font(.caption)
        }
    }

    private var debugSection: some View {
        Section("Debug (Temporary)") {
            Button("Force Upload All Data") {
                Task { @MainActor in
                    let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
                    for card in cards {
                        await syncService.upload(card)
                    }
                    
                    let credits = (try? context.fetch(FetchDescriptor<Credit>())) ?? []
                    for credit in credits {
                        await syncService.upload(credit)
                    }
                    
                    let logs = (try? context.fetch(FetchDescriptor<PeriodLog>())) ?? []
                    for log in logs {
                        await syncService.upload(log)
                    }
                    
                    print("Finished uploading \(cards.count) cards, \(credits.count) credits, and \(logs.count) logs.")
                }
            }
        }
    }

    private var developerSignatureSection: some View {
        Section {
            TimelineView(.animation) { timeline in
                // Slowly cycle the gradient phase — one full cycle every ~12 seconds.
                let phase = timeline.date.timeIntervalSinceReferenceDate * (1.0 / 12.0)
                let t = phase.truncatingRemainder(dividingBy: 1.0)

                // Apple Intelligence palette: purple → pink → blue → orange
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
        // Fetch and delete all existing cards (cascade deletes credits + period logs)
        let existing = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        for card in existing {
            context.delete(card)
        }
        try? context.save()

        // Re-seed
        hasSeededData = false
        SeedDataManager.seed(context: context)
        hasSeededData = true

        // Reschedule notifications with freshly fetched data
        Task { @MainActor in
            let freshCards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
            let allCredits = freshCards.flatMap { $0.credits }
            NotificationManager.shared.rescheduleAll(credits: allCredits)
        }

        showResetDone = true
    }
}

struct JoinFamilySheet: View {
    @Environment(\.dismiss) private var dismiss
    var modelContext: ModelContext
    
    @State private var inputID: String = ""
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Enter Family ID"), footer: Text("Joining a family will wipe your current local cards and replace them with the shared family data. This cannot be undone.")) {
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
                // Only enable the button if they've pasted something
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

#Preview {
    SettingsView()
        .modelContainer(for: [Card.self, Credit.self, PeriodLog.self], inMemory: true)
}
