import Foundation
import SwiftData

struct SeedCredit {
    let name: String
    let value: Double
    let timeframe: TimeframeType
    var reminderDaysBefore: Int = 5
}

struct SeedCardData {
    let name: String
    let annualFee: Double
    let gradientStart: String
    let gradientEnd: String
    let credits: [SeedCredit]
}

struct SeedDataManager {

    static let seedCards: [SeedCardData] = [
        SeedCardData(
            name: "Amex Gold",
            annualFee: 325,
            gradientStart: "#B76E79",
            gradientEnd: "#C9A96E",
            credits: [
                SeedCredit(name: "Uber Cash", value: 10, timeframe: .monthly),
                SeedCredit(name: "Dining Credit", value: 10, timeframe: .monthly),
                SeedCredit(name: "Dunkin' Credit", value: 7, timeframe: .monthly),
                SeedCredit(name: "Resy Credit", value: 50, timeframe: .semiAnnual),
            ]
        ),
        SeedCardData(
            name: "Amex Platinum",
            annualFee: 895,
            gradientStart: "#A8A9AD",
            gradientEnd: "#E8E8E8",
            credits: [
                SeedCredit(name: "Airline Fee Credit", value: 200, timeframe: .annual),
                SeedCredit(name: "Uber Cash ($35 in Dec)", value: 15, timeframe: .monthly),
                SeedCredit(name: "Saks Fifth Avenue Credit", value: 50, timeframe: .semiAnnual),
                SeedCredit(name: "Digital Entertainment Credit", value: 20, timeframe: .monthly),
                SeedCredit(name: "Hotel Credit", value: 200, timeframe: .annual),
                SeedCredit(name: "CLEAR Plus Credit", value: 189, timeframe: .annual),
            ]
        ),
        SeedCardData(
            name: "Capital One Venture X",
            annualFee: 395,
            gradientStart: "#1C1C1C",
            gradientEnd: "#4A4A4A",
            credits: [
                SeedCredit(name: "Travel Credit", value: 300, timeframe: .annual),
            ]
        ),
        SeedCardData(
            name: "Chase Sapphire Preferred",
            annualFee: 95,
            gradientStart: "#0C2340",
            gradientEnd: "#1A5276",
            credits: [
                SeedCredit(name: "Hotel Credit", value: 50, timeframe: .annual),
            ]
        ),
        SeedCardData(
            name: "Marriott Bonvoy Bevy",
            annualFee: 250,
            gradientStart: "#8A1538",
            gradientEnd: "#D64309",
            credits: []
        ),
        SeedCardData(
            name: "Citi Strata Premier",
            annualFee: 95,
            gradientStart: "#003B70",
            gradientEnd: "#00A3E0",
            credits: [
                SeedCredit(name: "Hotel Credit", value: 100, timeframe: .annual),
            ]
        ),
        SeedCardData(
            name: "Amex Delta Gold",
            annualFee: 150,
            gradientStart: "#C9A96E",
            gradientEnd: "#003366",
            credits: [
                SeedCredit(name: "Delta Stays Credit", value: 100, timeframe: .annual),
                SeedCredit(name: "Delta Flight Credit ($10k spend)", value: 200, timeframe: .annual),
            ]
        ),
        SeedCardData(
            name: "Bank of America Premium Rewards",
            annualFee: 95,
            gradientStart: "#BB0000",
            gradientEnd: "#C0392B",
            credits: [
                SeedCredit(name: "Airline Incidental Credit", value: 100, timeframe: .annual),
            ]
        ),
    ]

    @MainActor
    static func seed(context: ModelContext, now: Date = Date()) {
        var seededCards: [Card] = []

        for (index, seedCard) in seedCards.enumerated() {
            let card = Card(
                name: seedCard.name,
                annualFee: seedCard.annualFee,
                gradientStartHex: seedCard.gradientStart,
                gradientEndHex: seedCard.gradientEnd,
                sortOrder: index
            )
            context.insert(card)
            seededCards.append(card)

            for seedCredit in seedCard.credits {
                let credit = Credit(
                    name: seedCredit.name,
                    totalValue: seedCredit.value,
                    timeframe: seedCredit.timeframe,
                    reminderDaysBefore: seedCredit.reminderDaysBefore
                )
                credit.card = card
                card.credits.append(credit)
                context.insert(credit)

                let window = PeriodEngine.currentPeriod(for: credit, referenceDate: now)
                let log = PeriodLog(
                    periodLabel: window.label,
                    periodStart: window.start,
                    periodEnd: window.end,
                    status: .pending
                )
                log.credit = credit
                credit.periodLogs.append(log)
                context.insert(log)
            }
        }

        do {
            try context.save()
        } catch {
            print("SeedDataManager save error: \(error)")
        }

        NotificationManager.shared.rescheduleAllPaymentReminders(cards: seededCards)
    }
}
