import Foundation
import SwiftData
import FirebaseCore
import FirebaseFirestore

// MARK: - PeriodLogRepository

/// Owns the Firestore real-time listener for `PeriodLog` documents and applies
/// incoming changes to the local SwiftData store.
///
/// Like `CreditRepository`, handles out-of-order delivery by creating stub
/// Credit parents when a log arrives before its parent Credit has synced.
@MainActor
final class PeriodLogRepository {

    private let db: Firestore
    private let userID: String
    private weak var context: ModelContext?
    private let deviceID: String
    private var listener: ListenerRegistration?

    init(db: Firestore, userID: String, context: ModelContext, deviceID: String) {
        self.db       = db
        self.userID   = userID
        self.context  = context
        self.deviceID = deviceID
    }

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

    private var collection: CollectionReference {
        db.collection("users").document(userID).collection("periodLogs")
    }

    private func handleSnapshot(_ snapshot: QuerySnapshot?) {
        guard let snapshot, let context else { return }
        var didChange = false

        for change in snapshot.documentChanges {
            let docID = change.document.documentID

            if change.type == .removed {
                guard !change.document.metadata.hasPendingWrites else { continue }
                if let item = fetchLog(id: docID, in: context) { context.delete(item); didChange = true }
                continue
            }

            guard change.type == .added || change.type == .modified else { continue }
            guard !change.document.metadata.hasPendingWrites else { continue }

            let data = change.document.data()
            if data["deviceID"] as? String == deviceID, !change.document.metadata.fromCache { continue }

            if (data["deletedAt"] as? Timestamp) != nil {
                if let item = fetchLog(id: docID, in: context) { context.delete(item); didChange = true }
                continue
            }

            if applyChange(docID: docID, data: data, context: context) { didChange = true }
        }

        if didChange { try? context.save() }
    }

    @discardableResult
    private func applyChange(docID: String, data: [String: Any], context: ModelContext) -> Bool {
        guard let uuid = UUID(uuidString: docID),
              let dto = FirestorePeriodLogDTO(from: data) else { return false }

        let log: PeriodLog
        var isNew = false

        if let existing = fetchLog(id: docID, in: context) {
            log = existing
        } else {
            log = PeriodLog(periodLabel: "Syncing...", periodStart: Date(), periodEnd: Date(), status: .pending)
            log.id = uuid
            context.insert(log)
            isNew = true
        }

        var changed = isNew || log.apply(dto)

        // Wire the parent Credit relationship — handles out-of-order snapshot delivery.
        if let creditID = dto.creditID, log.credit?.id.uuidString != creditID {
            guard let parentID = UUID(uuidString: creditID) else { return changed }
            var parentCredit = fetchCredit(id: creditID, in: context)

            if parentCredit == nil {
                let stub = Credit(name: "Syncing...", totalValue: 0, timeframe: .monthly, reminderDaysBefore: 5)
                stub.id = parentID
                context.insert(stub)
                parentCredit = stub
            }

            if let parent = parentCredit {
                log.credit = parent
                if !parent.periodLogs.contains(where: { $0.id == log.id }) {
                    parent.periodLogs.append(log)
                }
                changed = true
            }
        }

        return changed
    }

    private func fetchLog(id: String, in context: ModelContext) -> PeriodLog? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<PeriodLog>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchCredit(id: String, in context: ModelContext) -> Credit? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<Credit>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

// MARK: - PeriodLog DTO Apply

extension PeriodLog {
    @discardableResult
    func apply(_ dto: FirestorePeriodLogDTO) -> Bool {
        var changed = false
        if periodLabel   != dto.periodLabel   { periodLabel = dto.periodLabel;     changed = true }
        if periodStart   != dto.periodStart   { periodStart = dto.periodStart;     changed = true }
        if periodEnd     != dto.periodEnd     { periodEnd = dto.periodEnd;         changed = true }
        if status        != dto.status        { status = dto.status;               changed = true }
        if claimedAmount != dto.claimedAmount { claimedAmount = dto.claimedAmount; changed = true }
        return changed
    }
}
