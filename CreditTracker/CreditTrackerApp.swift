import SwiftUI
import SwiftData
import FirebaseCore

@main
struct CreditTrackerApp: App {
    // Wire up the UIKit AppDelegate (needed for FCM token registration and
    // background silent-push handling). SwiftUI's scene lifecycle is still
    // the primary driver — the AppDelegate just augments it.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @AppStorage(Constants.hasSeededDataKey) private var hasSeededData = false
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Shared Model Container

    /// Exposed as a nonisolated static so AppDelegate can create `ModelContext`
    /// instances for background silent-push handling without crossing actor boundaries.
    nonisolated(unsafe) static var sharedModelContainer: ModelContainer?

    let modelContainer: ModelContainer = {
        // Add FamilySettings to the schema alongside the existing root models.
        let schema = Schema([Card.self, Credit.self, PeriodLog.self, BonusCard.self, FamilySettings.self, LoyaltyProgram.self, CardApplication.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            // Cache the container before the MainActor context is established so
            // AppDelegate.didReceiveRemoteNotification can access it safely.
            CreditTrackerApp.sharedModelContainer = container
            return container
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    init() {
        // FirebaseApp.configure() reads GoogleService-Info.plist from the app bundle.
        // Guard against a missing or misconfigured plist so the app doesn't crash.
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           plist["GOOGLE_APP_ID"] != nil {
            FirebaseApp.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .modelContainer(modelContainer)
                .task {
                    // Wire up sync and start cloud listeners before any user interaction.
                    FirestoreSyncService.shared.configure(modelContext: modelContainer.mainContext)
                    FirestoreSyncService.shared.startListening()

                    if !hasSeededData {
                        await SeedDataManager.seed(context: modelContainer.mainContext)
                        hasSeededData = true
                        await NotificationManager.shared.requestPermission()
                    }

                    // Ensure FamilySettings singleton exists (migrates from @AppStorage
                    // on first launch after the upgrade).
                    ensureFamilySettingsSingleton()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                evaluatePeriodsOnActivation()
                Task { @MainActor in
                    FirestoreSyncService.shared.startListening()
                }
            case .background:
                Task { @MainActor in
                    FirestoreSyncService.shared.stopListening()
                }
            default:
                break
            }
        }
    }

    // MARK: - Period Evaluation

    private func evaluatePeriodsOnActivation() {
        let context = modelContainer.mainContext
        do {
            let cards      = try context.fetch(FetchDescriptor<Card>())
            let allCredits = cards.flatMap { $0.credits }
            PeriodEngine.evaluateAndAdvancePeriods(for: allCredits, context: context)
            try context.save()
            Task { @MainActor in
                NotificationManager.shared.rescheduleAll(credits: allCredits)
                NotificationManager.shared.rescheduleAllPaymentReminders(cards: cards)
            }
        } catch {
            print("Period evaluation error: \(error)")
        }
    }

    // MARK: - FamilySettings Bootstrap

    /// Creates the FamilySettings singleton if it doesn't exist yet, migrating values
    /// from legacy @AppStorage keys so existing users keep their Discord reminder time.
    private func ensureFamilySettingsSingleton() {
        let context = modelContainer.mainContext
        var descriptor = FetchDescriptor<FamilySettings>()
        descriptor.fetchLimit = 1
        guard (try? context.fetch(descriptor).first) == nil else { return }

        // First launch after upgrade: seed from legacy UserDefaults values.
        let settings = FamilySettings.migratingFromAppStorage()
        context.insert(settings)
        try? context.save()

        // Push to Firestore — creates the document if it doesn't exist yet.
        Task { await FirestoreSyncService.shared.upload(settings) }
    }
}

// MARK: - MainTabView

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Cards", systemImage: "creditcard.fill") {
                DashboardView()
            }
            Tab("Rewards", systemImage: "star.fill") {
                RewardsDashboardView()
            }
            Tab("Hub", systemImage: "square.grid.2x2.fill") {
                HubView()
            }
            Tab("History", systemImage: "clock.fill") {
                HistoryView()
            }
            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
        }
    }
}
