import Foundation
import SwiftData
import FirebaseCore
import FirebaseFirestore

// MARK: - LoyaltyProgramRepository

/// Owns the Firestore real-time listener for `LoyaltyProgram` documents.
///
/// The `notes` field requires special handling: the DTO's `notesPresent` flag
/// distinguishes between "field absent in Firestore doc" (don't touch local
/// value) and "field present as NSNull" (remote device cleared notes — propagate nil).
@MainActor
final class LoyaltyProgramRepository {

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
            MainActor.assumeIsolated {
                guard let self, let context = self.context else { return }
                self.handleSnapshot(snapshot, context: context, deviceID: self.deviceID)
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    private var collection: CollectionReference {
        db.collection("users").document(userID).collection("loyaltyPrograms")
    }

    private func handleSnapshot(_ snapshot: QuerySnapshot?, context: ModelContext, deviceID: String) {
        guard let snapshot else { return }
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
              let dto = FirestoreLoyaltyProgramDTO(from: data) else { return false }

        let program: LoyaltyProgram
        var isNew = false

        if let existing = fetch(id: docID, in: context) {
            program = existing
        } else {
            program = LoyaltyProgram(programName: "Syncing...", category: .other,
                                     ownerName: "", gradientStartHex: "#000000", gradientEndHex: "#333333")
            program.id = uuid
            context.insert(program)
            isNew = true
        }

        return isNew || program.apply(dto)
    }

    private func fetch(id: String, in context: ModelContext) -> LoyaltyProgram? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<LoyaltyProgram>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

// MARK: - LoyaltyProgram DTO Apply

extension LoyaltyProgram {
    @discardableResult
    func apply(_ dto: FirestoreLoyaltyProgramDTO) -> Bool {
        var changed = false
        if programName      != dto.programName      { programName = dto.programName;           changed = true }
        if category         != dto.category         { category = dto.category;                 changed = true }
        if ownerName        != dto.ownerName        { ownerName = dto.ownerName;               changed = true }
        if gradientStartHex != dto.gradientStartHex { gradientStartHex = dto.gradientStartHex; changed = true }
        if gradientEndHex   != dto.gradientEndHex   { gradientEndHex = dto.gradientEndHex;     changed = true }
        if pointBalance     != dto.pointBalance     { pointBalance = dto.pointBalance;         changed = true }
        if lastUpdated      != dto.lastUpdated      { lastUpdated = dto.lastUpdated;           changed = true }
        // notes: only apply when the field was present in the Firestore document.
        // This prevents absent fields (older docs) from clearing user-set notes.
        if dto.notesPresent, notes != dto.notes     { notes = dto.notes;                       changed = true }
        return changed
    }
}
