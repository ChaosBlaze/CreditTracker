import SwiftUI
import SwiftData
import FirebaseCore

@main
struct CreditTrackerApp: App {
    @AppStorage(Constants.hasSeededDataKey) private var hasSeededData = false
    @Environment(\.scenePhase) private var scenePhase

    let modelContainer: ModelContainer = {
        let schema = Schema([Card.self, Credit.self, PeriodLog.self, BonusCard.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    init() {
        // FirebaseApp.configure() reads GoogleService-Info.plist from the app bundle.
        // Guard against a missing or misconfigured plist so the app doesn't crash at launch.
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
                    // Wire up the sync service to the live model context and start listening.
                    // This runs on the MainActor and is guaranteed to execute before any
                    // user interaction reaches the views.
                    FirestoreSyncService.shared.configure(modelContext: modelContainer.mainContext)
                    FirestoreSyncService.shared.startListening()

                    if !hasSeededData {
                        await SeedDataManager.seed(context: modelContainer.mainContext)
                        hasSeededData = true
                        await NotificationManager.shared.requestPermission()
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                evaluatePeriodsOnActivation()
                // Re-attach listeners when returning from background.
                // startListening() is a no-op if already listening.
                Task { @MainActor in
                    FirestoreSyncService.shared.startListening()
                }
            case .background:
                // Remove listeners to avoid unnecessary network traffic while backgrounded.
                Task { @MainActor in
                    FirestoreSyncService.shared.stopListening()
                }
            default:
                break
            }
        }
    }

    private func evaluatePeriodsOnActivation() {
        let context = modelContainer.mainContext
        do {
            let cards = try context.fetch(FetchDescriptor<Card>())
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
}

struct MainTabView: View {
    var body: some View {
        TabView {
            // "Credits" tab renamed to "Cards" — payment settings now live inside
            // each card section on this tab rather than in a separate Cards tab.
            Tab("Cards", systemImage: "creditcard.fill") {
                DashboardView()
            }
            Tab("Bonuses", systemImage: "sparkles") {
                BonusView()
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
