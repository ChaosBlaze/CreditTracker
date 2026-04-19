import Foundation

// MARK: - Sync State

/// Observable state exposed by SyncCoordinator.
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
            return "SyncCoordinator must be configured before use. Call configure(modelContext:) at app startup."
        case .uploadFailed(let id, let error):
            return "Firestore upload failed for item \(id): \(error.localizedDescription)"
        case .localWipeFailed(let error):
            return "Failed to wipe local data before joining family sync: \(error.localizedDescription)"
        }
    }
}

// MARK: - Syncable Protocol

/// Marks a SwiftData model as uploadable to Firestore.
///
/// ## Extending Sync to New Model Types
/// 1. Add a `FirestoreSyncable` conformance extension below.
/// 2. Create a corresponding Repository in Services/ that owns the listener.
/// 3. Register the repository in `SyncCoordinator.buildRepositories(context:)`.
/// 4. Call `SyncCoordinator.shared.upload(_:)` after any local save.
///
/// The protocol covers upload serialization only. Download/merge logic lives in
/// each model's Repository, keeping responsibilities clearly separated.
protocol FirestoreSyncable {
    /// Stable string identifier used as the Firestore document ID.
    var syncID: String { get }
    /// Sub-collection name under `users/{userID}/` in Firestore.
    static var firestoreCollectionName: String { get }
    /// Returns the model fields to write to Firestore.
    /// Do NOT include `updatedAt` or `deviceID` — SyncCoordinator appends those.
    func firestorePayload() -> [String: Any]
}

// MARK: - PeriodLog Conformance

extension PeriodLog: FirestoreSyncable {
    var syncID: String { id.uuidString }

    static var firestoreCollectionName: String { "periodLogs" }

    func firestorePayload() -> [String: Any] {
        var payload: [String: Any] = [
            "periodLabel":   periodLabel,
            "periodStart":   periodStart,
            "periodEnd":     periodEnd,
            "status":        status,
            "claimedAmount": claimedAmount
        ]
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
            "name":                      name,
            "annualFee":                 annualFee,
            "gradientStartHex":          gradientStartHex,
            "gradientEndHex":            gradientEndHex,
            "sortOrder":                 sortOrder,
            "paymentReminderEnabled":    paymentReminderEnabled,
            "paymentReminderDaysBefore": paymentReminderDaysBefore,
            "annualFeeReminderEnabled":  annualFeeReminderEnabled
        ]
        if let dueDay  = paymentDueDay  { payload["paymentDueDay"]  = dueDay }
        if let feeDate = annualFeeDate  { payload["annualFeeDate"]   = feeDate }
        return payload
    }
}

// MARK: - FamilySettings Conformance

extension FamilySettings: FirestoreSyncable {

    /// Fixed document ID — all family devices share this single Firestore document.
    var syncID: String { "family-discord-settings" }

    static var firestoreCollectionName: String { "familySettings" }

    func firestorePayload() -> [String: Any] {
        [
            "discordReminderEnabled": discordReminderEnabled,
            "discordReminderHour":    discordReminderHour,
            "discordReminderMinute":  discordReminderMinute,
            "lastModifiedByToken":    lastModifiedByToken
        ]
    }
}

// MARK: - BonusCard Conformance

extension BonusCard: FirestoreSyncable {
    var syncID: String { id.uuidString }
    static var firestoreCollectionName: String { "bonusCards" }

    func firestorePayload() -> [String: Any] {
        [
            "cardName":                   cardName,
            "bonusAmount":                bonusAmount,
            "dateOpened":                 dateOpened,
            "accountHolderName":          accountHolderName,
            "miscNotes":                  miscNotes,
            "requiresPurchases":          requiresPurchases,
            "purchaseTarget":             purchaseTarget,
            "currentPurchaseAmount":      currentPurchaseAmount,
            "requiresDirectDeposit":      requiresDirectDeposit,
            "directDepositTarget":        directDepositTarget,
            "currentDirectDepositAmount": currentDirectDepositAmount,
            "requiresOther":              requiresOther,
            "otherDescription":           otherDescription,
            "isOtherCompleted":           isOtherCompleted,
            "isCompleted":                isCompleted
        ]
    }
}

// MARK: - Credit Conformance

extension Credit: FirestoreSyncable {
    var syncID: String { id.uuidString }
    static var firestoreCollectionName: String { "credits" }

    func firestorePayload() -> [String: Any] {
        var payload: [String: Any] = [
            "name":                  name,
            "totalValue":            totalValue,
            "timeframe":             timeframe,
            "reminderDaysBefore":    reminderDaysBefore,
            "customReminderEnabled": customReminderEnabled
        ]
        if let cardID = card?.id.uuidString {
            payload["cardID"] = cardID
        }
        return payload
    }
}

// MARK: - CardApplication Conformance

extension CardApplication: FirestoreSyncable {
    var syncID: String { id.uuidString }
    static var firestoreCollectionName: String { "cardApplications" }

    func firestorePayload() -> [String: Any] {
        [
            "cardName":        cardName,
            "issuer":          issuer,
            "cardType":        cardType,
            "applicationDate": applicationDate,
            "isApproved":      isApproved,
            "player":          player,
            "creditLimit":     creditLimit,
            "annualFee":       annualFee,
            "notes":           notes
        ]
    }
}

// MARK: - LoyaltyProgram Conformance

extension LoyaltyProgram: FirestoreSyncable {
    var syncID: String { id.uuidString }
    static var firestoreCollectionName: String { "loyaltyPrograms" }

    func firestorePayload() -> [String: Any] {
        var payload: [String: Any] = [
            "programName":      programName,
            "category":         category,
            "ownerName":        ownerName,
            "pointBalance":     pointBalance,
            "lastUpdated":      lastUpdated,
            "gradientStartHex": gradientStartHex,
            "gradientEndHex":   gradientEndHex
        ]
        // Always write `notes` — when nil, NSNull() signals a remote clear.
        // Without this, clearing notes locally never propagates to other devices.
        payload["notes"] = notes ?? NSNull()
        return payload
    }
}
