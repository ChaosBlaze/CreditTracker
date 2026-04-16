import Foundation
import SwiftData

// MARK: - LoyaltyProgram

/// SwiftData model representing a single loyalty program account (airline miles,
/// hotel points, or bank reward points) owned by a specific family member.
///
/// Conforms to `FirestoreSyncable` so balances stay in sync across all family devices.
/// Gradient hex colors drive the Liquid Glass tint on the card row.
@Model
final class LoyaltyProgram {
    var id: UUID = UUID()
    var programName: String = ""
    /// Raw value of `LoyaltyCategory` — stored as String for SwiftData compatibility.
    var category: String = LoyaltyCategory.other.rawValue
    /// Family member who owns this account (e.g. "Shekar", "Wife").
    var ownerName: String = ""
    var pointBalance: Int = 0
    /// Timestamp of the last balance update — displayed in the edit sheet.
    var lastUpdated: Date = Date()
    var gradientStartHex: String = "#1A1A2E"
    var gradientEndHex: String = "#16213E"
    var notes: String? = nil

    // MARK: - Computed

    var categoryType: LoyaltyCategory {
        LoyaltyCategory(rawValue: category) ?? .other
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        programName: String,
        category: LoyaltyCategory,
        ownerName: String,
        pointBalance: Int = 0,
        lastUpdated: Date = Date(),
        gradientStartHex: String,
        gradientEndHex: String,
        notes: String? = nil
    ) {
        self.id = id
        self.programName = programName
        self.category = category.rawValue
        self.ownerName = ownerName
        self.pointBalance = pointBalance
        self.lastUpdated = lastUpdated
        self.gradientStartHex = gradientStartHex
        self.gradientEndHex = gradientEndHex
        self.notes = notes
    }
}
