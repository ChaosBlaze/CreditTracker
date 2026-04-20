import Foundation
import SwiftData
import FirebaseCore
import FirebaseFirestore

// MARK: - CreditRepository

/// Owns the Firestore real-time listener for `Credit` documents and applies
/// incoming changes to the local SwiftData store.
///
/// Handles out-of-order delivery: when a Credit document arrives before its
/// parent Card has synced, a stub Card is created so the relationship is wired
/// immediately. The stub's fields are filled in when the Card snapshot fires.
@MainActor
final class CreditRepository {

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
        db.collection("users").document(userID).collection("credits")
    }

    private func handleSnapshot(_ snapshot: QuerySnapshot?) {
        guard let snapshot, let context else { return }
        var didChange = false

        for change in snapshot.documentChanges {
            let docID = change.document.documentID

            if change.type == .removed {
                guard !change.document.metadata.hasPendingWrites else { continue }
                if let item = fetchCredit(id: docID, in: context) { context.delete(item); didChange = true }
                continue
            }

            guard change.type == .added || change.type == .modified else { continue }
            guard !change.document.metadata.hasPendingWrites else { continue }

            let data = change.document.data()
            if data["deviceID"] as? String == deviceID, !change.document.metadata.isFromCache { continue }

            if (data["deletedAt"] as? Timestamp) != nil {
                if let item = fetchCredit(id: docID, in: context) { context.delete(item); didChange = true }
                continue
            }

            if applyChange(docID: docID, data: data, context: context) { didChange = true }
        }

        if didChange { try? context.save() }
    }

    @discardableResult
    private func applyChange(docID: String, data: [String: Any], context: ModelContext) -> Bool {
        guard let uuid = UUID(uuidString: docID),
              let dto = FirestoreCreditDTO(from: data) else { return false }

        let credit: Credit
        var isNew = false

        if let existing = fetchCredit(id: docID, in: context) {
            credit = existing
        } else {
            credit = Credit(name: "Syncing...", totalValue: 0, timeframe: .monthly, reminderDaysBefore: 5)
            credit.id = uuid
            context.insert(credit)
            isNew = true
        }

        var changed = isNew || credit.apply(dto)

        // Wire the parent Card relationship — handles out-of-order snapshot delivery.
        if let cardID = dto.cardID, credit.card?.id.uuidString != cardID {
            guard let parentID = UUID(uuidString: cardID) else { return changed }
            var parentCard = fetchCard(id: cardID, in: context)

            if parentCard == nil {
                // Create a stub Card; it will be fully populated when the Card
                // snapshot fires (which may arrive before or after this one).
                let stub = Card(name: "Syncing...", annualFee: 0,
                                gradientStartHex: "#000000", gradientEndHex: "#000000", sortOrder: 0)
                stub.id = parentID
                context.insert(stub)
                parentCard = stub
            }

            if let parent = parentCard {
                credit.card = parent
                if !parent.credits.contains(where: { $0.id == credit.id }) {
                    parent.credits.append(credit)
                }
                changed = true
            }
        }

        return changed
    }

    private func fetchCredit(id: String, in context: ModelContext) -> Credit? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<Credit>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchCard(id: String, in context: ModelContext) -> Card? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

// MARK: - Credit DTO Apply

extension Credit {
    @discardableResult
    func apply(_ dto: FirestoreCreditDTO) -> Bool {
        var changed = false
        if name                  != dto.name                  { name = dto.name;                           changed = true }
        if totalValue            != dto.totalValue            { totalValue = dto.totalValue;               changed = true }
        if timeframe             != dto.timeframe             { timeframe = dto.timeframe;                 changed = true }
        if reminderDaysBefore    != dto.reminderDaysBefore    { reminderDaysBefore = dto.reminderDaysBefore; changed = true }
        if customReminderEnabled != dto.customReminderEnabled { customReminderEnabled = dto.customReminderEnabled; changed = true }
        return changed
    }
}
