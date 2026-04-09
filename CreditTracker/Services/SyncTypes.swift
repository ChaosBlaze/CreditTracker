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
        [
            "name": name,
            "annualFee": annualFee,
            "gradientStartHex": gradientStartHex,
            "gradientEndHex": gradientEndHex,
            "sortOrder": sortOrder
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
