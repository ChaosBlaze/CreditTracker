import Foundation
import FirebaseFirestore

// MARK: - Firestore Data Transfer Objects (DTOs)
//
// Lightweight, type-safe value structs that parse Firestore [String: Any]
// dictionaries into Swift types with proper Timestamp → Date conversion.
//
// ## Why DTOs instead of Codable?
// Firestore returns custom `Timestamp` objects inside [String: Any], which
// cannot be decoded by Swift's JSONDecoder without FirebaseFirestoreSwift's
// @ServerTimestamp property wrapper. These DTOs give equivalent type safety
// without the additional dependency, and keep the failable parsing logic in
// one place per model rather than scattered across a 826-line monolith.
//
// ## Usage
// Each DTO has a failable init?(from data: [String: Any]) that returns nil if
// required fields are missing (hard failure), and falls back to sensible
// defaults for optional fields (graceful degradation).
//
// Repositories call:
//   guard let dto = FirestoreCardDTO(from: doc.data()) else { return false }
//   return card.apply(dto)
//
// ## Soft Deletes (Phase 0)
// Every DTO exposes a `deletedAt: Date?` field. Documents where this field is
// non-nil are treated as remote deletions by the repositories' snapshot
// handlers — they delete the local SwiftData row rather than applying changes.

// MARK: - Card DTO

struct FirestoreCardDTO {
    let name: String
    let annualFee: Double
    let gradientStartHex: String
    let gradientEndHex: String
    let sortOrder: Int
    let paymentReminderEnabled: Bool
    let paymentReminderDaysBefore: Int
    let paymentDueDay: Int?          // nil when field absent (not yet configured)
    let annualFeeReminderEnabled: Bool
    let annualFeeDate: Date?         // nil when field absent (user hasn't set a date)
    let deletedAt: Date?

    init?(from data: [String: Any]) {
        guard let name = data["name"] as? String else { return nil }
        self.name                    = name
        self.annualFee               = (data["annualFee"] as? Double) ?? (data["annualFee"] as? NSNumber)?.doubleValue ?? 0
        self.gradientStartHex        = data["gradientStartHex"] as? String ?? "#A8A9AD"
        self.gradientEndHex          = data["gradientEndHex"]   as? String ?? "#E8E8E8"
        self.sortOrder               = data["sortOrder"]        as? Int    ?? 0
        self.paymentReminderEnabled  = data["paymentReminderEnabled"]      as? Bool ?? true
        self.paymentReminderDaysBefore = data["paymentReminderDaysBefore"] as? Int  ?? 3
        // paymentDueDay and annualFeeDate: distinguish "absent" from "null"
        // so that a remote clear (NSNull) propagates as nil rather than being ignored.
        self.paymentDueDay           = data.keys.contains("paymentDueDay")  ? data["paymentDueDay"]  as? Int  : nil
        self.annualFeeReminderEnabled = data["annualFeeReminderEnabled"] as? Bool ?? false
        self.annualFeeDate           = (data["annualFeeDate"] as? Timestamp)?.dateValue()
        self.deletedAt               = (data["deletedAt"]    as? Timestamp)?.dateValue()
    }
}

// MARK: - Credit DTO

struct FirestoreCreditDTO {
    let name: String
    let totalValue: Double
    let timeframe: String
    let reminderDaysBefore: Int
    let customReminderEnabled: Bool
    let cardID: String?
    let deletedAt: Date?

    init?(from data: [String: Any]) {
        guard let name = data["name"] as? String else { return nil }
        self.name                 = name
        self.totalValue           = (data["totalValue"] as? Double) ?? (data["totalValue"] as? NSNumber)?.doubleValue ?? 0
        self.timeframe            = data["timeframe"]            as? String ?? TimeframeType.monthly.rawValue
        self.reminderDaysBefore   = data["reminderDaysBefore"]   as? Int    ?? 5
        self.customReminderEnabled = data["customReminderEnabled"] as? Bool  ?? true
        self.cardID               = data["cardID"]               as? String
        self.deletedAt            = (data["deletedAt"] as? Timestamp)?.dateValue()
    }
}

// MARK: - PeriodLog DTO

struct FirestorePeriodLogDTO {
    let periodLabel: String
    let periodStart: Date
    let periodEnd: Date
    let status: String
    let claimedAmount: Double
    let creditID: String?
    let deletedAt: Date?

    init?(from data: [String: Any]) {
        guard
            let label   = data["periodLabel"] as? String,
            let startTS = data["periodStart"] as? Timestamp,
            let endTS   = data["periodEnd"]   as? Timestamp
        else { return nil }
        self.periodLabel   = label
        self.periodStart   = startTS.dateValue()
        self.periodEnd     = endTS.dateValue()
        self.status        = data["status"]   as? String ?? PeriodStatus.pending.rawValue
        self.claimedAmount = (data["claimedAmount"] as? Double) ?? (data["claimedAmount"] as? NSNumber)?.doubleValue ?? 0
        self.creditID      = data["creditID"] as? String
        self.deletedAt     = (data["deletedAt"] as? Timestamp)?.dateValue()
    }
}

// MARK: - BonusCard DTO

struct FirestoreBonusCardDTO {
    let cardName: String
    let bonusAmount: String
    let dateOpened: Date
    let accountHolderName: String
    let miscNotes: String
    let requiresPurchases: Bool
    let purchaseTarget: Double
    let currentPurchaseAmount: Double
    let requiresDirectDeposit: Bool
    let directDepositTarget: Double
    let currentDirectDepositAmount: Double
    let requiresOther: Bool
    let otherDescription: String
    let isOtherCompleted: Bool
    let isCompleted: Bool
    let deletedAt: Date?

    init?(from data: [String: Any]) {
        guard let cardName = data["cardName"] as? String else { return nil }
        self.cardName                  = cardName
        self.bonusAmount               = data["bonusAmount"]               as? String ?? ""
        self.dateOpened                = (data["dateOpened"] as? Timestamp)?.dateValue() ?? Date()
        self.accountHolderName         = data["accountHolderName"]         as? String ?? ""
        self.miscNotes                 = data["miscNotes"]                 as? String ?? ""
        self.requiresPurchases         = data["requiresPurchases"]         as? Bool   ?? false
        self.purchaseTarget            = (data["purchaseTarget"]           as? Double) ?? (data["purchaseTarget"]           as? NSNumber)?.doubleValue ?? 0
        self.currentPurchaseAmount     = (data["currentPurchaseAmount"]    as? Double) ?? (data["currentPurchaseAmount"]    as? NSNumber)?.doubleValue ?? 0
        self.requiresDirectDeposit     = data["requiresDirectDeposit"]     as? Bool   ?? false
        self.directDepositTarget       = (data["directDepositTarget"]      as? Double) ?? (data["directDepositTarget"]      as? NSNumber)?.doubleValue ?? 0
        self.currentDirectDepositAmount = (data["currentDirectDepositAmount"] as? Double) ?? (data["currentDirectDepositAmount"] as? NSNumber)?.doubleValue ?? 0
        self.requiresOther             = data["requiresOther"]             as? Bool   ?? false
        self.otherDescription          = data["otherDescription"]          as? String ?? ""
        self.isOtherCompleted          = data["isOtherCompleted"]          as? Bool   ?? false
        self.isCompleted               = data["isCompleted"]               as? Bool   ?? false
        self.deletedAt                 = (data["deletedAt"] as? Timestamp)?.dateValue()
    }
}

// MARK: - LoyaltyProgram DTO

struct FirestoreLoyaltyProgramDTO {
    let programName: String
    let category: String
    let ownerName: String
    let gradientStartHex: String
    let gradientEndHex: String
    let pointBalance: Int
    let lastUpdated: Date
    /// `notesPresent` distinguishes "field absent" from "field set to nil".
    /// When false, the repository leaves the local `notes` value unchanged.
    let notesPresent: Bool
    let notes: String?
    let deletedAt: Date?

    init?(from data: [String: Any]) {
        guard let programName = data["programName"] as? String else { return nil }
        self.programName     = programName
        self.category        = data["category"]        as? String ?? LoyaltyCategory.other.rawValue
        self.ownerName       = data["ownerName"]       as? String ?? ""
        self.gradientStartHex = data["gradientStartHex"] as? String ?? "#000000"
        self.gradientEndHex   = data["gradientEndHex"]   as? String ?? "#333333"
        self.pointBalance    = (data["pointBalance"] as? Int) ?? (data["pointBalance"] as? NSNumber)?.intValue ?? 0
        self.lastUpdated     = (data["lastUpdated"] as? Timestamp)?.dateValue() ?? Date()
        self.notesPresent    = data.keys.contains("notes")
        self.notes           = data["notes"] as? String
        self.deletedAt       = (data["deletedAt"] as? Timestamp)?.dateValue()
    }
}

// MARK: - CardApplication DTO

struct FirestoreCardApplicationDTO {
    let cardName: String
    let issuer: String
    let cardType: String
    let applicationDate: Date
    let isApproved: Bool
    let player: String
    let creditLimit: Double
    let annualFee: Double
    let notes: String
    let deletedAt: Date?

    init?(from data: [String: Any]) {
        guard let cardName = data["cardName"] as? String else { return nil }
        self.cardName        = cardName
        self.issuer          = data["issuer"]    as? String ?? ""
        self.cardType        = data["cardType"]  as? String ?? ""
        self.applicationDate = (data["applicationDate"] as? Timestamp)?.dateValue() ?? Date()
        self.isApproved      = data["isApproved"] as? Bool ?? false
        self.player          = data["player"]    as? String ?? ""
        self.creditLimit     = (data["creditLimit"] as? Double) ?? (data["creditLimit"] as? NSNumber)?.doubleValue ?? 0
        self.annualFee       = (data["annualFee"]   as? Double) ?? (data["annualFee"]   as? NSNumber)?.doubleValue ?? 0
        self.notes           = data["notes"]     as? String ?? ""
        self.deletedAt       = (data["deletedAt"] as? Timestamp)?.dateValue()
    }
}

// MARK: - FamilySettings DTO

struct FirestoreFamilySettingsDTO {
    let discordReminderEnabled: Bool
    let discordReminderHour: Int
    let discordReminderMinute: Int
    let lastModifiedByToken: String

    // FamilySettings has no deletedAt — it's a singleton that should persist.
    init?(from data: [String: Any]) {
        self.discordReminderEnabled = data["discordReminderEnabled"] as? Bool ?? false
        self.discordReminderHour    = data["discordReminderHour"]    as? Int  ?? Constants.discordReminderDefaultHour
        self.discordReminderMinute  = data["discordReminderMinute"]  as? Int  ?? Constants.discordReminderDefaultMinute
        self.lastModifiedByToken    = data["lastModifiedByToken"]    as? String ?? ""
    }
}
