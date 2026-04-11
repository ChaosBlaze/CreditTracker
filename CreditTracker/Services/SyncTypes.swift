import Foundation

// MARK: - Sync State

/// Observable state exposed by FirestoreSyncService.
enum SyncState: Equatable {
    case idle
    case syncing
    case error(String)
}

// MARK: - Sync Errors

enum SyncError: LocalizedError {
    case notConfigured
    case uploadFailed(id: String, underlying: Error)
    case localWipeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "FirestoreSyncService must be configured before use. Call configure(modelContext:) at app startup."
        case .uploadFailed(let id, let error):
            return "Firestore upload failed for item \(id): \(error.localizedDescription)"
        case .localWipeFailed(let error):
            return "Failed to wipe local data before joining family sync: \(error.localizedDescription)"
        }
    }
}

// MARK: - Syncable Protocol

/// Marks a SwiftData model as syncable to Firestore.
///
/// To extend the sync scope to additional models in the future:
/// 1. Add a conformance extension below.
/// 2. Call `FirestoreSyncService.shared.upload(_:)` after any local save.
///
/// The protocol is intentionally minimal — it only prescribes serialization.
/// All network and conflict-resolution logic lives in `FirestoreSyncService`.
protocol FirestoreSyncable {
    /// Stable string identifier used as the Firestore document ID.
    var syncID: String { get }
    /// Sub-collection name under the user document in Firestore.
    static var firestoreCollectionName: String { get }
    /// Returns the fields to write to Firestore.
    /// Do NOT include `updatedAt` here — the service appends a server timestamp.
    func firestorePayload() -> [String: Any]
}

// MARK: - PeriodLog Conformance

extension PeriodLog: FirestoreSyncable {
    var syncID: String { id.uuidString }

    static var firestoreCollectionName: String { "periodLogs" }

    func firestorePayload() -> [String: Any] {
        var payload: [String: Any] = [
            "periodLabel": periodLabel,
            "periodStart": periodStart,
            "periodEnd": periodEnd,
            "status": status,
            "claimedAmount": claimedAmount
        ]
        
        // Foreign Key to link back to parent Credit
        if let creditID = credit?.id.uuidString {
            payload["creditID"] = creditID
        }
        
        return payload
    }
}

// MARK: - Card Conformance

extension Card: FirestoreSyncable {
    var syncID: String { id.uuidString }
    static var firestoreCollectionName: String { "cards" }

    func firestorePayload() -> [String: Any] {
        var payload: [String: Any] = [
            "name": name,
            "annualFee": annualFee,
            "gradientStartHex": gradientStartHex,
            "gradientEndHex": gradientEndHex,
            "sortOrder": sortOrder,
            // Payment reminder fields — always included so other devices can read them.
            "paymentReminderEnabled": paymentReminderEnabled,
            "paymentReminderDaysBefore": paymentReminderDaysBefore
        ]
        // paymentDueDay is optional — only write it when set to keep the
        // Firestore document clean for cards that haven't configured a due date yet.
        if let dueDay = paymentDueDay {
            payload["paymentDueDay"] = dueDay
        }
        return payload
    }
}

// MARK: - FamilySettings Conformance

extension FamilySettings: FirestoreSyncable {

    /// Fixed document ID — all family devices share this single Firestore document.
    /// Using a constant rather than the model's UUID guarantees convergence: every
    /// device upserts the same path, so there's never more than one cloud document.
    var syncID: String { "family-discord-settings" }

    static var firestoreCollectionName: String { "familySettings" }

    func firestorePayload() -> [String: Any] {
        [
            "discordReminderEnabled":  discordReminderEnabled,
            "discordReminderHour":     discordReminderHour,
            "discordReminderMinute":   discordReminderMinute,
            // Stamped by the writing device so receivers know whether to alert the user.
            "lastModifiedByToken":     lastModifiedByToken
        ]
    }
}

// MARK: - BonusCard Conformance

extension BonusCard: FirestoreSyncable {
    var syncID: String { id.uuidString }

    /// Stored in its own top-level sub-collection so it can be queried independently
    /// of the card/credit/periodLog hierarchy.
    static var firestoreCollectionName: String { "bonusCards" }

    func firestorePayload() -> [String: Any] {
        [
            // Core identity
            "cardName":                    cardName,
            "bonusAmount":                 bonusAmount,
            "dateOpened":                  dateOpened,

            // QoL fields (Phase 1)
            "accountHolderName":           accountHolderName,
            "miscNotes":                   miscNotes,

            // Minimum spend requirement
            "requiresPurchases":           requiresPurchases,
            "purchaseTarget":              purchaseTarget,
            "currentPurchaseAmount":       currentPurchaseAmount,

            // Direct deposit requirement
            "requiresDirectDeposit":       requiresDirectDeposit,
            "directDepositTarget":         directDepositTarget,
            "currentDirectDepositAmount":  currentDirectDepositAmount,

            // Catch-all "other" requirement
            "requiresOther":               requiresOther,
            "otherDescription":            otherDescription,
            "isOtherCompleted":            isOtherCompleted,

            // Completion state — synced so marking done on one device reflects everywhere
            "isCompleted":                 isCompleted
        ]
    }
}

// MARK: - Credit Conformance

extension Credit: FirestoreSyncable {
    var syncID: String { id.uuidString }
    static var firestoreCollectionName: String { "credits" }

    func firestorePayload() -> [String: Any] {
        var payload: [String: Any] = [
            "name": name,
            "totalValue": totalValue,
            "timeframe": timeframe,
            "reminderDaysBefore": reminderDaysBefore,
            "customReminderEnabled": customReminderEnabled
        ]
        
        // Foreign Key to link back to parent Card
        if let cardID = card?.id.uuidString {
            payload["cardID"] = cardID
        }
        
        return payload
    }
}
