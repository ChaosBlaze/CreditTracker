import Foundation
import SwiftData
import FirebaseCore
import FirebaseFirestore

// MARK: - CardRepository

/// Owns the Firestore real-time listener for `Card` documents and applies
/// incoming changes to the local SwiftData store.
///
/// Extracted from `FirestoreSyncService` as part of the Phase 1 repository split.
/// One repository per model type: each is independently testable, independently
/// stoppable, and adds zero lines to sibling repositories when fields change.
@MainActor
final class CardRepository {

    // MARK: Dependencies

    private let db: Firestore
    private let userID: String
    private weak var context: ModelContext?
    private let deviceID: String

    // MARK: State

    private var listener: ListenerRegistration?

    // MARK: Init

    init(db: Firestore, userID: String, context: ModelContext, deviceID: String) {
        self.db       = db
        self.userID   = userID
        self.context  = context
        self.deviceID = deviceID
    }

    // MARK: Listener Lifecycle

    func startListening() {
        guard listener == nil else { return }
        listener = collection.addSnapshotListener { [weak self] snapshot, _ in
            self?.handleSnapshot(snapshot)
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: Private — Snapshot Handling

    private var collection: CollectionReference {
        db.collection("users").document(userID).collection("cards")
    }

    private func handleSnapshot(_ snapshot: QuerySnapshot?) {
        guard let snapshot, let context else { return }
        var didChange = false

        for change in snapshot.documentChanges {
            let docID = change.document.documentID

            // Hard delete (Firestore document removed).
            if change.type == .removed {
                guard !change.document.metadata.hasPendingWrites else { continue }
                if let item = fetch(id: docID, in: context) { context.delete(item); didChange = true }
                continue
            }

            guard change.type == .added || change.type == .modified else { continue }
            guard !change.document.metadata.hasPendingWrites else { continue }

            let data = change.document.data()

            // Skip writes authored by this device — deviceID replaces pendingUploadIDs.
            if data["deviceID"] as? String == deviceID, !change.document.metadata.isFromCache { continue }

            // Soft-delete: treat deletedAt field as a remote deletion signal.
            if (data["deletedAt"] as? Timestamp) != nil {
                if let item = fetch(id: docID, in: context) { context.delete(item); didChange = true }
                continue
            }

            if applyChange(docID: docID, data: data, context: context) { didChange = true }
        }

        if didChange { try? context.save() }
    }

    // MARK: Private — Apply Change

    @discardableResult
    private func applyChange(docID: String, data: [String: Any], context: ModelContext) -> Bool {
        guard let uuid = UUID(uuidString: docID),
              let dto = FirestoreCardDTO(from: data) else { return false }

        let card: Card
        var isNew = false

        if let existing = fetch(id: docID, in: context) {
            card = existing
        } else {
            card = Card(name: "Syncing...", annualFee: 0,
                        gradientStartHex: "#000000", gradientEndHex: "#000000", sortOrder: 0)
            card.id = uuid
            context.insert(card)
            isNew = true
        }

        return isNew || card.apply(dto)
    }

    // MARK: Private — Fetch Helper

    private func fetch(id: String, in context: ModelContext) -> Card? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

// MARK: - Card DTO Apply

extension Card {
    /// Applies only fields that differ from the DTO — minimises SwiftData dirty tracking
    /// and avoids unnecessary UI refreshes for unchanged values.
    ///
    /// - Returns: `true` if at least one field was updated.
    @discardableResult
    func apply(_ dto: FirestoreCardDTO) -> Bool {
        var changed = false
        if name                      != dto.name                      { name = dto.name;                                           changed = true }
        if annualFee                 != dto.annualFee                 { annualFee = dto.annualFee;                                 changed = true }
        if gradientStartHex          != dto.gradientStartHex          { gradientStartHex = dto.gradientStartHex;                   changed = true }
        if gradientEndHex            != dto.gradientEndHex            { gradientEndHex = dto.gradientEndHex;                       changed = true }
        if sortOrder                 != dto.sortOrder                 { sortOrder = dto.sortOrder;                                 changed = true }
        if paymentReminderEnabled    != dto.paymentReminderEnabled    { paymentReminderEnabled = dto.paymentReminderEnabled;       changed = true }
        if paymentReminderDaysBefore != dto.paymentReminderDaysBefore { paymentReminderDaysBefore = dto.paymentReminderDaysBefore; changed = true }
        if paymentDueDay             != dto.paymentDueDay             { paymentDueDay = dto.paymentDueDay;                         changed = true }
        if annualFeeReminderEnabled  != dto.annualFeeReminderEnabled  { annualFeeReminderEnabled = dto.annualFeeReminderEnabled;   changed = true }
        if annualFeeDate             != dto.annualFeeDate             { annualFeeDate = dto.annualFeeDate;                         changed = true }
        return changed
    }
}
