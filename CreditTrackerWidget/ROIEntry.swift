import WidgetKit
import Foundation

struct MonthlyWidgetData: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
}

struct ROIEntry: TimelineEntry {
    let date: Date
    let totalFees: Double
    let totalExtracted: Double
    let monthlyData: [MonthlyWidgetData]
    let cardCount: Int

    var netROI: Double { totalExtracted - totalFees }
    var isPositive: Bool { netROI >= 0 }

    static var placeholder: ROIEntry {
        ROIEntry(
            date: Date(),
            totalFees: 1285,
            totalExtracted: 847,
            monthlyData: [
                MonthlyWidgetData(label: "Jan", value: 65),
                MonthlyWidgetData(label: "Feb", value: 120),
                MonthlyWidgetData(label: "Mar", value: 85),
                MonthlyWidgetData(label: "Apr", value: 140),
                MonthlyWidgetData(label: "May", value: 200),
                MonthlyWidgetData(label: "Jun", value: 237),
            ],
            cardCount: 5
        )
    }
}
