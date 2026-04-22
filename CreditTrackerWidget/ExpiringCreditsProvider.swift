import WidgetKit
import SwiftData
import Foundation

struct ExpiringCreditsProvider: TimelineProvider {

    func placeholder(in context: Context) -> ExpiringCreditsEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ExpiringCreditsEntry) -> Void) {
        completion(context.isPreview ? .placeholder : fetchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ExpiringCreditsEntry>) -> Void) {
        let entry = fetchEntry()
        // Refresh at the soonest period expiry, or in 1 hour – whichever comes first
        let oneHour = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let nextUpdate = entry.items.first.map { min($0.periodEnd, oneHour) } ?? oneHour
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    // MARK: - Data Fetching

    private func fetchEntry() -> ExpiringCreditsEntry {
        let schema = Schema([Card.self, Credit.self, PeriodLog.self, BonusCard.self])
        let container: ModelContainer
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            return ExpiringCreditsEntry(date: Date(), items: [])
        }

        let context = container.mainContext
        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        let now = Date()
        var items: [ExpiringCreditItem] = []

        for card in cards {
            for credit in card.credits {
                let window = PeriodEngine.currentPeriod(for: credit, referenceDate: now)

                guard let log = credit.periodLogs.first(where: { $0.periodLabel == window.label }) else {
                    continue
                }

                let status = PeriodStatus(rawValue: log.status) ?? .pending
                guard status == .pending || status == .partiallyClaimed else { continue }

                let daysRemaining = max(0, DateHelpers.daysUntil(log.periodEnd, from: now))
                let fillFraction = credit.totalValue > 0
                    ? min(log.claimedAmount / credit.totalValue, 1.0)
                    : 0.0

                items.append(ExpiringCreditItem(
                    id: credit.id,
                    creditName: credit.name,
                    cardName: card.name,
                    value: credit.totalValue,
                    fillFraction: fillFraction,
                    daysRemaining: daysRemaining,
                    periodEnd: log.periodEnd,
                    gradientStartHex: card.gradientStartHex,
                    gradientEndHex: card.gradientEndHex
                ))
            }
        }

        // Soonest expiring first; break ties by highest value
        items.sort {
            if $0.daysRemaining != $1.daysRemaining { return $0.daysRemaining < $1.daysRemaining }
            return $0.value > $1.value
        }

        return ExpiringCreditsEntry(date: now, items: Array(items.prefix(3)))
    }
}
