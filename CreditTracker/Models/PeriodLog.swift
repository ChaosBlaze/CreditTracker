import Foundation
import SwiftData

@Model
final class PeriodLog {
    var id: UUID = UUID()
    var periodLabel: String = ""
    var periodStart: Date = Date()
    var periodEnd: Date = Date()
    var status: String = PeriodStatus.pending.rawValue
    var claimedAmount: Double = 0.0

    var credit: Credit?

    var periodStatus: PeriodStatus {
        get { PeriodStatus(rawValue: status) ?? .pending }
        set { status = newValue.rawValue }
    }

    var fillFraction: Double {
        guard let credit = credit, credit.totalValue > 0 else { return 0 }
        return min(claimedAmount / credit.totalValue, 1.0)
    }

    init(
        id: UUID = UUID(),
        periodLabel: String,
        periodStart: Date,
        periodEnd: Date,
        status: PeriodStatus = .pending,
        claimedAmount: Double = 0.0
    ) {
        self.id = id
        self.periodLabel = periodLabel
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.status = status.rawValue
        self.claimedAmount = claimedAmount
    }
}
