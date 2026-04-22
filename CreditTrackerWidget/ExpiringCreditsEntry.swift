import WidgetKit
import Foundation

struct ExpiringCreditItem: Identifiable {
    let id: UUID
    let creditName: String
    let cardName: String
    let value: Double
    let fillFraction: Double
    let daysRemaining: Int
    let periodEnd: Date
    let gradientStartHex: String
    let gradientEndHex: String
}

struct ExpiringCreditsEntry: TimelineEntry {
    let date: Date
    let items: [ExpiringCreditItem]

    var isEmpty: Bool { items.isEmpty }

    static var placeholder: ExpiringCreditsEntry {
        let cal = Calendar.current
        let now = Date()
        return ExpiringCreditsEntry(date: now, items: [
            ExpiringCreditItem(
                id: UUID(),
                creditName: "Dining Credit",
                cardName: "Amex Gold",
                value: 10,
                fillFraction: 0.0,
                daysRemaining: 3,
                periodEnd: cal.date(byAdding: .day, value: 3, to: now)!,
                gradientStartHex: "#B76E79",
                gradientEndHex: "#C9A96E"
            ),
            ExpiringCreditItem(
                id: UUID(),
                creditName: "Uber Cash",
                cardName: "Amex Platinum",
                value: 15,
                fillFraction: 0.5,
                daysRemaining: 8,
                periodEnd: cal.date(byAdding: .day, value: 8, to: now)!,
                gradientStartHex: "#A8A9AD",
                gradientEndHex: "#E8E8E8"
            ),
            ExpiringCreditItem(
                id: UUID(),
                creditName: "Hotel Credit",
                cardName: "Chase Sapphire",
                value: 50,
                fillFraction: 0.6,
                daysRemaining: 15,
                periodEnd: cal.date(byAdding: .day, value: 15, to: now)!,
                gradientStartHex: "#0C2340",
                gradientEndHex: "#1A5276"
            )
        ])
    }
}
