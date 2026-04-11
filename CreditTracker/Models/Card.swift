import Foundation
import SwiftData

@Model
final class Card {
    var id: UUID = UUID()
    var name: String = ""
    var annualFee: Double = 0.0
    var gradientStartHex: String = "#A8A9AD"
    var gradientEndHex: String = "#E8E8E8"
    var sortOrder: Int = 0
    var paymentDueDay: Int? = nil
    var paymentReminderDaysBefore: Int = 3
    var paymentReminderEnabled: Bool = true

    /// The date the annual fee renews. Used to fire a 30-day advance notification.
    /// Nil until the user sets it in CardPaymentSettingsView.
    var annualFeeDate: Date? = nil

    /// When true, a `UNCalendarNotificationTrigger` fires 30 days before `annualFeeDate`.
    /// Stored as a SwiftData field so Firestore sync propagates the preference to other devices.
    var annualFeeReminderEnabled: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Credit.card)
    var credits: [Credit] = []

    init(
        id: UUID = UUID(),
        name: String,
        annualFee: Double,
        gradientStartHex: String,
        gradientEndHex: String,
        sortOrder: Int = 0,
        paymentDueDay: Int? = nil,
        paymentReminderDaysBefore: Int = 3,
        paymentReminderEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.annualFee = annualFee
        self.gradientStartHex = gradientStartHex
        self.gradientEndHex = gradientEndHex
        self.sortOrder = sortOrder
        self.paymentDueDay = paymentDueDay
        self.paymentReminderDaysBefore = paymentReminderDaysBefore
        self.paymentReminderEnabled = paymentReminderEnabled
    }
}
