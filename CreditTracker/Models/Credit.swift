import Foundation
import SwiftData

@Model
final class Credit {
    var id: UUID = UUID()
    var name: String = ""
    var totalValue: Double = 0.0
    var timeframe: String = TimeframeType.monthly.rawValue
    var reminderDaysBefore: Int = 5
    var customReminderEnabled: Bool = true

    var card: Card?

    @Relationship(deleteRule: .cascade, inverse: \PeriodLog.credit)
    var periodLogs: [PeriodLog] = []

    var timeframeType: TimeframeType {
        get { TimeframeType(rawValue: timeframe) ?? .monthly }
        set { timeframe = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        totalValue: Double,
        timeframe: TimeframeType = .monthly,
        reminderDaysBefore: Int = 5,
        customReminderEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.totalValue = totalValue
        self.timeframe = timeframe.rawValue
        self.reminderDaysBefore = reminderDaysBefore
        self.customReminderEnabled = customReminderEnabled
    }
}
