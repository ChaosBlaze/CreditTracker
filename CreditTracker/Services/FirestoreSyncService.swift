import Foundation
import SwiftData
import FirebaseCore
import FirebaseFirestore

// MARK: - FirestoreSyncService

/// A lightweight Firestore sync bus that mirrors PeriodLog state across devices.
///
/// ## Architecture
/// SwiftData is the authoritative source of truth. Firestore is a dumb mirror that
/// stores only the fields declared in `FirestoreSyncable.firestorePayload()`.
///
/// ## Data Flow
/// ```
/// User action → SwiftData save → upload(_:) → Firestore
/// Remote change → Firestore snapshot → applySnapshot → SwiftData save → UI refresh
/// ```
///
/// ## Conflict Resolution
/// Last-write-wins via Firestore server timestamps. The server timestamp of the most
/// recent write to a document is authoritative. Suitable for single-user multi-device use.
///
/// ## Firestore Document Path
/// ```
/// /users/{userID}/periodLogs/{periodLog.id}
/// ```
///
/// ## Multi-Device Sync
/// Requires a shared `userID` across devices. By default a stable device-scoped UUID
/// is used, which provides single-device cloud backup. Call `setUserID(_:)` with a
/// Firebase Auth UID after sign-in to enable true cross-device sync.
@MainActor
@Observable
final class FirestoreSyncService {

    static let shared = FirestoreSyncService()

    // MARK: - Observable State

    private(set) var syncState: SyncState = .idle
    private(set) var lastSyncedAt: Date? = nil

    // MARK: - Private State

    private var db: Firestore { Firestore.firestore() }
    private var modelContext: ModelContext?
    private var activeListeners: [ListenerRegistration] = []

    /// Document IDs for PeriodLogs we have written locally but whose server
    /// confirmation has not yet arrived via the snapshot listener.
    ///
    /// Purpose: prevents applying our own writes back to SwiftData as remote changes.
    /// Each ID is inserted after a successful local write and removed when the
    /// Firestore listener delivers the server-confirmed version (hasPendingWrites == false).
    private var pendingUploadIDs: Set<String> = []

    /// Firestore path namespace for this user.
    /// Persisted across launches so PeriodLog documents accumulate under the same path.
    private(set) var userID: String = {
        if let stored = UserDefaults.standard.string(forKey: Constants.firestoreUserIDKey) {
            return stored
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: Constants.firestoreUserIDKey)
        return id
    }()

    private init() {}

    // MARK: - Setup

    /// Configures the service with the app's live model context.
    /// Must be called before `startListening()` or `upload(_:)`.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Overrides the user ID — e.g. after Firebase Auth sign-in for cross-device sync.
    /// Tears down existing listeners and restarts them under the new Firestore path.
    func setUserID(_ id: String) {
        guard id != userID else { return }
        stopListening()
        userID = id
        UserDefaults.standard.set(id, forKey: Constants.firestoreUserIDKey)
        startListening()
    }

    // MARK: - Listener Lifecycle

    /// Attaches a real-time Firestore listener for PeriodLog documents.
    ///
    /// - Safe to call multiple times: a second call while already listening is a no-op.
    /// - Call on `scenePhase == .active`.
    func startListening() {
        guard modelContext != nil, activeListeners.isEmpty, FirebaseApp.app() != nil else { return }

        let registration = collection(for: PeriodLog.self)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot else { return }
                Task { @MainActor in
                    self.applySnapshot(snapshot)
                }
            }
        activeListeners.append(registration)
    }

    /// Removes all Firestore listeners to avoid background network traffic.
    /// Call on `scenePhase == .background`.
    func stopListening() {
        activeListeners.forEach { $0.remove() }
        activeListeners.removeAll()
    }

    // MARK: - Upload (SwiftData → Firestore)

    /// Uploads the syncable fields of a PeriodLog to Firestore.
    ///
    /// Always call *after* `context.save()` so local state is committed first.
    /// Uses `merge: true` so only declared sync fields are touched — any extra
    /// Firestore fields (e.g. future server-side analytics) are preserved.
    ///
    /// Firestore's offline persistence means the write is queued locally if the
    /// device is offline and flushed automatically when connectivity returns.
    func upload(_ periodLog: PeriodLog) async {
        guard FirebaseApp.app() != nil else { return }
        let docID = periodLog.syncID
        syncState = .syncing

        var payload = periodLog.firestorePayload()
        payload["updatedAt"] = FieldValue.serverTimestamp()

        do {
            try await collection(for: PeriodLog.self)
                .document(docID)
                .setData(payload, merge: true)

            // Mark as pending after a successful local write.
            // The listener will consume this entry when the server confirms the write.
            pendingUploadIDs.insert(docID)
            lastSyncedAt = Date()
        } catch {
            // A hard write failure (e.g. security rules rejection).
            // Don't insert into pendingUploadIDs — let the listener apply Firestore's state.
            syncState = .error(
                SyncError.uploadFailed(id: docID, underlying: error).localizedDescription
                ?? "Upload failed"
            )
        }
    }

    // MARK: - Snapshot Handler (Firestore → SwiftData)

    private func applySnapshot(_ snapshot: QuerySnapshot) {
        guard let context = modelContext else { return }
        var didApplyChanges = false

        for change in snapshot.documentChanges {
            guard change.type == .added || change.type == .modified else { continue }

            let docID = change.document.documentID

            // Skip local writes not yet confirmed by the server.
            // `hasPendingWrites == true` always means the write originated on this device
            // and has not yet been acknowledged — it is never a remote change.
            if change.document.metadata.hasPendingWrites { continue }

            // Consume the server confirmation of our own upload.
            // Without this check, our own writes would be echoed back as "remote" changes.
            if pendingUploadIDs.remove(docID) != nil { continue }

            // Genuine remote write from another device — merge into local SwiftData.
            if applyRemoteChange(change.document.data(), forDocID: docID, into: context) {
                didApplyChanges = true
            }
        }

        // Only move to idle from syncing — preserve error state across snapshots.
        if pendingUploadIDs.isEmpty, case .syncing = syncState {
            syncState = .idle
        }
        if didApplyChanges { try? context.save() }
    }

    // MARK: - Merge Logic

    /// Applies incoming Firestore fields to the matching local PeriodLog.
    ///
    /// Compares each field before writing to avoid marking the SwiftData context
    /// as dirty when the remote value is identical to the local value.
    ///
    /// - Returns: `true` if at least one field was updated.
    @discardableResult
    private func applyRemoteChange(
        _ data: [String: Any],
        forDocID docID: String,
        into context: ModelContext
    ) -> Bool {
        guard let periodLog = fetchPeriodLog(id: docID, in: context) else {
            // No local PeriodLog for this Firestore document.
            // This can occur when Card/Credit definitions have not been seeded on this
            // device yet. Silently skip — sync will converge once the user adds the card.
            return false
        }

        var changed = false

        if let remoteStatus = data["status"] as? String,
           remoteStatus != periodLog.status {
            periodLog.status = remoteStatus
            changed = true
        }

        if let remoteAmountNumber = data["claimedAmount"] as? NSNumber {
            let remoteAmount = remoteAmountNumber.doubleValue
            if remoteAmount != periodLog.claimedAmount {
                periodLog.claimedAmount = remoteAmount
                changed = true
            }
        }

        return changed
    }

    // MARK: - Firestore Helpers

    private func collection<T: FirestoreSyncable>(for type: T.Type) -> CollectionReference {
        db.collection("users")
            .document(userID)
            .collection(T.firestoreCollectionName)
    }

    private func fetchPeriodLog(id: String, in context: ModelContext) -> PeriodLog? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let descriptor = FetchDescriptor<PeriodLog>(predicate: #Predicate { $0.id == uuid })
        return try? context.fetch(descriptor).first
    }
}
