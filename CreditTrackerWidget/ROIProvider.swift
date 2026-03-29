import WidgetKit
import SwiftData
import Foundation

struct ROIProvider: TimelineProvider {

    func placeholder(in context: Context) -> ROIEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ROIEntry) -> Void) {
        completion(context.isPreview ? .placeholder : fetchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ROIEntry>) -> Void) {
        let entry = fetchEntry()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    // MARK: - Data Fetching

    private func fetchEntry() -> ROIEntry {
        let schema = Schema([Card.self, Credit.self, PeriodLog.self, BonusCard.self, Achievement.self, UserStats.self])

        let container: ModelContainer
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            return ROIEntry(date: Date(), totalFees: 0, totalExtracted: 0, monthlyData: [], cardCount: 0)
        }

        let context = container.mainContext
        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        let totalFees = cards.reduce(0) { $0 + $1.annualFee }
        let allCredits = cards.flatMap { $0.credits }

        let currentYear = Calendar.current.component(.year, from: Date())
        var totalExtracted = 0.0
        var monthAmounts = [Int: Double]()

        for credit in allCredits {
            for log in credit.periodLogs {
                let cal = Calendar.current
                let year = cal.component(.year, from: log.periodStart)
                let month = cal.component(.month, from: log.periodStart)
                if year == currentYear && log.claimedAmount > 0 {
                    totalExtracted += log.claimedAmount
                    monthAmounts[month, default: 0] += log.claimedAmount
                }
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let monthlyData: [MonthlyWidgetData] = (1...12).compactMap { month in
            guard let amount = monthAmounts[month], amount > 0 else { return nil }
            guard let date = Calendar.current.date(from: DateComponents(year: currentYear, month: month)) else { return nil }
            return MonthlyWidgetData(label: formatter.string(from: date), value: amount)
        }

        return ROIEntry(
            date: Date(),
            totalFees: totalFees,
            totalExtracted: totalExtracted,
            monthlyData: monthlyData,
            cardCount: cards.count
        )
    }
}
