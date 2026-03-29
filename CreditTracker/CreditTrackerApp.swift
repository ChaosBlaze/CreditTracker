import SwiftUI
import SwiftData

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

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .modelContainer(modelContainer)
                .task {
                    if !hasSeededData {
                        SeedDataManager.seed(context: modelContainer.mainContext)
                        hasSeededData = true
                        await NotificationManager.shared.requestPermission()
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                evaluatePeriodsOnActivation()
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
            Tab("Credits", systemImage: "creditcard.fill") {
                DashboardView()
            }
            Tab("Cards", systemImage: "creditcard") {
                CardsView()
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
