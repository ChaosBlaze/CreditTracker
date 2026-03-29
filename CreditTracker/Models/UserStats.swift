import Foundation
import SwiftData

@Model
final class UserStats {
    var id: UUID = UUID()
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lifetimeSaved: Double = 0.0
    var totalClaimCount: Int = 0
    var lastClaimDate: Date? = nil

    init(
        id: UUID = UUID(),
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        lifetimeSaved: Double = 0.0,
        totalClaimCount: Int = 0,
        lastClaimDate: Date? = nil
    ) {
        self.id = id
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lifetimeSaved = lifetimeSaved
        self.totalClaimCount = totalClaimCount
        self.lastClaimDate = lastClaimDate
    }
}
