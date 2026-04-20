import Foundation
import SwiftData
import FirebaseCore
import FirebaseFirestore

// MARK: - BonusCardRepository

/// Owns the Firestore real-time listener for `BonusCard` documents.
/// BonusCards have no parent relationship, so there is no out-of-order
/// stub logic required — changes are applied directly.
@MainActor
final class BonusCardRepository {

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
        db.collection("users").document(userID).collection("bonusCards")
    }

    private func handleSnapshot(_ snapshot: QuerySnapshot?) {
        guard let snapshot, let context else { return }
        var didChange = false

        for change in snapshot.documentChanges {
            let docID = change.document.documentID

            if change.type == .removed {
                guard !change.document.metadata.hasPendingWrites else { continue }
                if let item = fetch(id: docID, in: context) { context.delete(item); didChange = true }
                continue
            }

            guard change.type == .added || change.type == .modified else { continue }
            guard !change.document.metadata.hasPendingWrites else { continue }

            let data = change.document.data()
            if data["deviceID"] as? String == deviceID, !change.document.metadata.isFromCache { continue }

            if (data["deletedAt"] as? Timestamp) != nil {
                if let item = fetch(id: docID, in: context) { context.delete(item); didChange = true }
                continue
            }

            if applyChange(docID: docID, data: data, context: context) { didChange = true }
        }

        if didChange { try? context.save() }
    }

    @discardableResult
    private func applyChange(docID: String, data: [String: Any], context: ModelContext) -> Bool {
        guard let uuid = UUID(uuidString: docID),
              let dto = FirestoreBonusCardDTO(from: data) else { return false }

        let bonus: BonusCard
        var isNew = false

        if let existing = fetch(id: docID, in: context) {
            bonus = existing
        } else {
            bonus = BonusCard(cardName: "Syncing...", bonusAmount: "")
            bonus.id = uuid
            context.insert(bonus)
            isNew = true
        }

        return isNew || bonus.apply(dto)
    }

    private func fetch(id: String, in context: ModelContext) -> BonusCard? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<BonusCard>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

// MARK: - BonusCard DTO Apply

extension BonusCard {
    @discardableResult
    func apply(_ dto: FirestoreBonusCardDTO) -> Bool {
        var changed = false
        if cardName                   != dto.cardName                   { cardName = dto.cardName;                                     changed = true }
        if bonusAmount                != dto.bonusAmount                { bonusAmount = dto.bonusAmount;                               changed = true }
        if dateOpened                 != dto.dateOpened                 { dateOpened = dto.dateOpened;                                 changed = true }
        if accountHolderName          != dto.accountHolderName          { accountHolderName = dto.accountHolderName;                   changed = true }
        if miscNotes                  != dto.miscNotes                  { miscNotes = dto.miscNotes;                                   changed = true }
        if requiresPurchases          != dto.requiresPurchases          { requiresPurchases = dto.requiresPurchases;                   changed = true }
        if purchaseTarget             != dto.purchaseTarget             { purchaseTarget = dto.purchaseTarget;                         changed = true }
        if currentPurchaseAmount      != dto.currentPurchaseAmount      { currentPurchaseAmount = dto.currentPurchaseAmount;           changed = true }
        if requiresDirectDeposit      != dto.requiresDirectDeposit      { requiresDirectDeposit = dto.requiresDirectDeposit;           changed = true }
        if directDepositTarget        != dto.directDepositTarget        { directDepositTarget = dto.directDepositTarget;               changed = true }
        if currentDirectDepositAmount != dto.currentDirectDepositAmount { currentDirectDepositAmount = dto.currentDirectDepositAmount; changed = true }
        if requiresOther              != dto.requiresOther              { requiresOther = dto.requiresOther;                           changed = true }
        if otherDescription           != dto.otherDescription           { otherDescription = dto.otherDescription;                     changed = true }
        if isOtherCompleted           != dto.isOtherCompleted           { isOtherCompleted = dto.isOtherCompleted;                     changed = true }
        if isCompleted                != dto.isCompleted                { isCompleted = dto.isCompleted;                               changed = true }
        return changed
    }
}
