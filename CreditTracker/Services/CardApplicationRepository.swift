import Foundation
import SwiftData
import FirebaseCore
import FirebaseFirestore

// MARK: - CardApplicationRepository

/// Owns the Firestore real-time listener for `CardApplication` documents.
/// CardApplications are independent records with no parent relationship.
@MainActor
final class CardApplicationRepository {

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
        db.collection("users").document(userID).collection("cardApplications")
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
            if data["deviceID"] as? String == deviceID, !change.document.metadata.fromCache { continue }

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
              let dto = FirestoreCardApplicationDTO(from: data) else { return false }

        let app: CardApplication
        var isNew = false

        if let existing = fetch(id: docID, in: context) {
            app = existing
        } else {
            app = CardApplication(cardName: "Syncing...", issuer: "")
            app.id = uuid
            context.insert(app)
            isNew = true
        }

        return isNew || app.apply(dto)
    }

    private func fetch(id: String, in context: ModelContext) -> CardApplication? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<CardApplication>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

// MARK: - CardApplication DTO Apply

extension CardApplication {
    @discardableResult
    func apply(_ dto: FirestoreCardApplicationDTO) -> Bool {
        var changed = false
        if cardName        != dto.cardName        { cardName = dto.cardName;               changed = true }
        if issuer          != dto.issuer          { issuer = dto.issuer;                   changed = true }
        if cardType        != dto.cardType        { cardType = dto.cardType;               changed = true }
        if applicationDate != dto.applicationDate { applicationDate = dto.applicationDate; changed = true }
        if isApproved      != dto.isApproved      { isApproved = dto.isApproved;           changed = true }
        if player          != dto.player          { player = dto.player;                   changed = true }
        if creditLimit     != dto.creditLimit     { creditLimit = dto.creditLimit;         changed = true }
        if annualFee       != dto.annualFee       { annualFee = dto.annualFee;             changed = true }
        if notes           != dto.notes           { notes = dto.notes;                     changed = true }
        return changed
    }
}
