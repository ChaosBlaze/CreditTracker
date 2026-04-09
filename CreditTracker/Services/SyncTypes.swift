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

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "FirestoreSyncService must be configured before use. Call configure(modelContext:) at app startup."
        case .uploadFailed(let id, let error):
            return "Firestore upload failed for PeriodLog \(id): \(error.localizedDescription)"
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

    /// Only `status` and `claimedAmount` are synced.
    /// Card and Credit definitions remain local/owner-managed.
    func firestorePayload() -> [String: Any] {
        [
            "status": status,
            "claimedAmount": claimedAmount
        ]
    }
}
