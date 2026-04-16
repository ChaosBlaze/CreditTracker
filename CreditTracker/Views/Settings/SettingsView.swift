import SwiftUI
import SwiftData
import UserNotifications

// MARK: - AppearanceMode

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return "Auto"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage(Constants.hasSeededDataKey) private var hasSeededData = false

    @Query private var settingsArray: [FamilySettings]
    @State private var notificationManager = NotificationManager.shared

    private var familySettings: FamilySettings? { settingsArray.first }

    var body: some View {
        NavigationStack {
            List {
                appearanceSection

                Section {
                    NavigationLink {
                        AccountSettingsView()
                    } label: {
                        settingsRow(
                            icon: "person.crop.circle.fill",
                            color: .blue,
                            title: "Account",
                            subtitle: "Family sync & device"
                        )
                    }

                    NavigationLink {
                        NotificationsSettingsView()
                    } label: {
                        settingsRow(
                            icon: "bell.fill",
                            color: .red,
                            title: "Notifications",
                            subtitle: notificationSubtitle
                        )
                    }

                    NavigationLink {
                        AboutSettingsView()
                    } label: {
                        settingsRow(
                            icon: "info.circle.fill",
                            color: Color(hue: 0.6, saturation: 0.5, brightness: 0.6),
                            title: "About",
                            subtitle: "CreditTracker v4.0"
                        )
                    }

                    NavigationLink {
                        OtherSettingsView()
                    } label: {
                        settingsRow(
                            icon: "ellipsis.circle.fill",
                            color: .orange,
                            title: "Other",
                            subtitle: "Data & debug tools"
                        )
                    }
                }

                developerSignatureSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .task {
                await notificationManager.checkStatus()
                ensureFamilySettingsSingleton()
            }
        }
    }

    // MARK: - Appearance Section

    @ViewBuilder
    private var appearanceSection: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.spring(duration: 0.25)) {
                            appearanceMode = mode
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 18, weight: .medium))
                            Text(mode.label)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            appearanceMode == mode
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    appearanceMode == mode ? Color.accentColor.opacity(0.4) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appearanceMode == mode ? .accent : .secondary)
                }
            }
            .padding(4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 13))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("Appearance")
        }
    }

    // MARK: - Settings Row Helper

    @ViewBuilder
    private func settingsRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Developer Signature

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
                    .font(.system(size: 14, weight: .medium))
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

    // MARK: - Notification Subtitle

    private var notificationSubtitle: String {
        switch notificationManager.authorizationStatus {
        case .authorized:   return "Enabled"
        case .denied:       return "Denied – tap to fix"
        case .provisional:  return "Provisional"
        default:            return "Not yet requested"
        }
    }

    // MARK: - FamilySettings Bootstrap

    private func ensureFamilySettingsSingleton() {
        guard settingsArray.isEmpty else { return }
        let settings = FamilySettings.migratingFromAppStorage()
        context.insert(settings)
        try? context.save()
        Task { await FirestoreSyncService.shared.upload(settings) }
    }
}

// MARK: - AccountSettingsView

struct AccountSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var syncService = FirestoreSyncService.shared
    @State private var showJoinFamilySheet = false

    var body: some View {
        List {
            firestoreSyncSection
            familySyncSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showJoinFamilySheet) {
            JoinFamilySheet(modelContext: context)
        }
    }

    // MARK: Firestore Sync

    private var firestoreSyncSection: some View {
        Section {
            HStack {
                Label("Status", systemImage: "arrow.triangle.2.circlepath.icloud")
                Spacer()
                syncStateBadge
            }

            HStack {
                Label("Last Synced", systemImage: "clock")
                Spacer()
                Group {
                    if let date = syncService.lastSyncedAt {
                        Text(date, style: .relative)
                    } else {
                        Text("Never")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            LabeledContent("Device ID", value: String(syncService.userID.prefix(8)) + "…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Sync")
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

    // MARK: Family Sync

    private var familySyncSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your Shared Family ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(syncService.userID)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button {
                        UIPasteboard.general.string = syncService.userID
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Button("Join Existing Family") {
                showJoinFamilySheet = true
            }
        } header: {
            Text("Family")
        } footer: {
            Text("Share your Family ID with others to sync cards and credits across devices.")
        }
    }
}

// MARK: - NotificationsSettingsView

struct NotificationsSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Constants.defaultReminderDaysKey) private var defaultReminderDays = Constants.defaultReminderDays
    @Query private var settingsArray: [FamilySettings]
    @State private var notificationManager = NotificationManager.shared

    private var familySettings: FamilySettings? { settingsArray.first }

    var body: some View {
        List {
            permissionSection
            creditRemindersSection
            discordSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .task { await notificationManager.checkStatus() }
    }

    // MARK: Permission

    private var permissionSection: some View {
        Section {
            HStack {
                Label("Permission", systemImage: "bell")
                Spacer()
                statusBadge
            }

            if notificationManager.authorizationStatus == .denied {
                Button {
                    openSettings()
                } label: {
                    Label("Open System Settings", systemImage: "arrow.up.right.square")
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

            Button {
                notificationManager.scheduleTestNotification()
            } label: {
                Label("Send Test Notification", systemImage: "bell.badge.waveform")
                    .foregroundStyle(.blue)
            }
        } header: {
            Text("Status")
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch notificationManager.authorizationStatus {
        case .authorized:
            badge("Enabled", color: .green)
        case .denied:
            badge("Denied", color: .red)
        case .provisional:
            badge("Provisional", color: .orange)
        default:
            Text("Not Requested")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func badge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }

    // MARK: Credit Reminders

    private var creditRemindersSection: some View {
        Section {
            Stepper(
                "Default: \(defaultReminderDays) day\(defaultReminderDays == 1 ? "" : "s") before",
                value: $defaultReminderDays,
                in: Constants.minReminderDays...Constants.maxReminderDays
            )
        } header: {
            Text("Credit Reminders")
        } footer: {
            Text("How many days before a credit expires to send a reminder. Applies to all credits unless overridden.")
        }
    }

    // MARK: Discord

    private var discordSection: some View {
        Section {
            Toggle("Discord Redeem Reminder", isOn: discordEnabledBinding)

            if familySettings?.discordReminderEnabled == true {
                DatePicker(
                    "Reminder Time",
                    selection: discordReminderTimeBinding,
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            Text("Discord")
        } footer: {
            Text("Sends a daily push notification reminding you to redeem Discord Nitro credits.")
        }
    }

    // MARK: Status Badge Helper

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: Discord Bindings

    private var discordEnabledBinding: Binding<Bool> {
        Binding(
            get: { familySettings?.discordReminderEnabled ?? false },
            set: { newValue in
                guard let settings = familySettings else { return }
                settings.discordReminderEnabled = newValue
                settings.lastModifiedByToken = UserDefaults.standard.string(forKey: Constants.fcmTokenKey) ?? ""
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
                Task { await FirestoreSyncService.shared.upload(settings) }
            }
        )
    }

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
                settings.discordReminderHour   = newHour
                settings.discordReminderMinute = newMinute
                settings.lastModifiedByToken = UserDefaults.standard.string(forKey: Constants.fcmTokenKey) ?? ""
                UserDefaults.standard.set(newHour,   forKey: Constants.discordReminderHourKey)
                UserDefaults.standard.set(newMinute, forKey: Constants.discordReminderMinuteKey)
                try? context.save()
                if settings.discordReminderEnabled {
                    notificationManager.cancelDiscordReminder()
                    notificationManager.scheduleDiscordReminder(hour: newHour, minute: newMinute)
                }
                Task { await FirestoreSyncService.shared.upload(settings) }
            }
        )
    }
}

// MARK: - AboutSettingsView

struct AboutSettingsView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("App",        value: "CreditTracker")
                LabeledContent("Version",    value: "4.0")
                LabeledContent("iOS Target", value: "26.0+")
                LabeledContent("Bundle ID",  value: Constants.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("App Info")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - OtherSettingsView

struct OtherSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Constants.hasSeededDataKey) private var hasSeededData = false
    @Query private var settingsArray: [FamilySettings]
    @State private var showResetConfirmation = false
    @State private var showResetDone = false

    private var familySettings: FamilySettings? { settingsArray.first }

    var body: some View {
        List {
            dataSection
            debugSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Other")
        .navigationBarTitleDisplayMode(.large)
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

    private var dataSection: some View {
        Section {
            Button {
                showResetConfirmation = true
            } label: {
                Label("Reset to Default Data", systemImage: "arrow.counterclockwise")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Removes all current cards and credits, then restores the original set of example cards.")
        }
    }

    private var debugSection: some View {
        Section {
            Button("Force Upload All Data") {
                Task { @MainActor in
                    let syncService = FirestoreSyncService.shared

                    let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
                    for card in cards { await syncService.upload(card) }

                    let credits = (try? context.fetch(FetchDescriptor<Credit>())) ?? []
                    for credit in credits { await syncService.upload(credit) }

                    let logs = (try? context.fetch(FetchDescriptor<PeriodLog>())) ?? []
                    for log in logs { await syncService.upload(log) }

                    if let settings = familySettings {
                        await syncService.upload(settings)
                    }

                    print("Uploaded \(cards.count) cards, \(credits.count) credits, \(logs.count) logs.")
                }
            }
        } header: {
            Text("Debug")
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
                            .foregroundStyle(.red)
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
