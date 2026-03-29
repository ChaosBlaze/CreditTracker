import SwiftUI
import SwiftData

@main
struct CreditTrackerApp: App {
    @AppStorage(Constants.hasSeededDataKey) private var hasSeededData = false
    @Environment(\.scenePhase) private var scenePhase

    let modelContainer: ModelContainer = {
        let schema = Schema([
            Card.self,
            Credit.self,
            PeriodLog.self,
            BonusCard.self,
            Achievement.self,
            UserStats.self
        ])
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
                    // Always seed achievements (idempotent)
                    GamificationEngine.seedAchievements(context: modelContainer.mainContext)
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

            // Update gamification streaks
            GamificationEngine.updateStreak(cards: cards, context: context)

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
    @Query(sort: \Card.sortOrder) private var cards: [Card]

    var body: some View {
        ZStack {
            // Animated MeshGradient background behind all tabs
            MeshGradientBackground(cards: Array(cards))

            // Dark charcoal base with subtle radial gradient
            RadialGradient(
                colors: [Color(hex: "#0A0A0F").opacity(0.7), Color(hex: "#0A0A0F")],
                center: .center,
                startRadius: 50,
                endRadius: 500
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            TabView {
                Tab("Credits", systemImage: "creditcard.fill") {
                    DashboardView()
                }
                Tab("Cards", systemImage: "rectangle.on.rectangle.angled") {
                    CardsView()
                }
                Tab("Bonuses", systemImage: "star.circle.fill") {
                    BonusView()
                }
                Tab("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
                    HistoryView()
                }
                Tab("Settings", systemImage: "gearshape.fill") {
                    SettingsView()
                }
            }
        }
    }
}
