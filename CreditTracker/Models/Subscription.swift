import Foundation
import SwiftData

@Model final class Subscription {
    var id: UUID = UUID()
    var name: String = ""
    var category: String = SubscriptionCategory.other.rawValue
    var cost: Double = 0.0
    var billingCycle: String = BillingCycle.monthly.rawValue
    var nextBillingDate: Date = Date()
    var isActive: Bool = true
    var reminderEnabled: Bool = true
    var reminderDaysBefore: Int = 3
    /// UUID string of the linked Card, or "" if none.
    var linkedCardID: String = ""
    /// UUID string of the linked Credit that offsets this cost, or "" if none.
    var linkedCreditID: String = ""
    var notes: String = ""

    init(
        id: UUID = UUID(),
        name: String,
        category: SubscriptionCategory = .other,
        cost: Double,
        billingCycle: BillingCycle = .monthly,
        nextBillingDate: Date,
        isActive: Bool = true,
        reminderEnabled: Bool = true,
        reminderDaysBefore: Int = 3,
        linkedCardID: String = "",
        linkedCreditID: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.category = category.rawValue
        self.cost = cost
        self.billingCycle = billingCycle.rawValue
        self.nextBillingDate = nextBillingDate
        self.isActive = isActive
        self.reminderEnabled = reminderEnabled
        self.reminderDaysBefore = reminderDaysBefore
        self.linkedCardID = linkedCardID
        self.linkedCreditID = linkedCreditID
        self.notes = notes
    }

    // MARK: - Computed

    var billingCycleType: BillingCycle {
        get { BillingCycle(rawValue: billingCycle) ?? .monthly }
        set { billingCycle = newValue.rawValue }
    }

    var categoryType: SubscriptionCategory {
        get { SubscriptionCategory(rawValue: category) ?? .other }
        set { category = newValue.rawValue }
    }

    /// Approximate monthly equivalent cost for totals.
    var monthlyCost: Double {
        cost * billingCycleType.monthlyMultiplier
    }

    /// Days from now until nextBillingDate (0 = today or past).
    var daysUntilRenewal: Int {
        max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: nextBillingDate)).day ?? 0)
    }

    /// Advances nextBillingDate forward by one billing cycle until it is in the future.
    /// Returns true if the date was mutated (caller should upload to Firestore).
    @discardableResult
    func advanceNextBillingDateIfPast() -> Bool {
        let cal = Calendar.current
        var didAdvance = false
        while nextBillingDate < Date() {
            let cycle = billingCycleType
            if let months = cycle.monthsPerCycle {
                nextBillingDate = cal.date(byAdding: .month, value: months, to: nextBillingDate) ?? nextBillingDate
            } else {
                // Weekly
                nextBillingDate = cal.date(byAdding: .weekOfYear, value: 1, to: nextBillingDate) ?? nextBillingDate
            }
            didAdvance = true
        }
        return didAdvance
    }
}
