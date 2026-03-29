import Foundation
import SwiftData

@Model
final class Achievement {
    var id: UUID = UUID()
    var key: String = ""
    var name: String = ""
    var icon: String = ""
    var unlockedAt: Date? = nil
    var requirement: String = ""

    var isUnlocked: Bool { unlockedAt != nil }

    init(
        id: UUID = UUID(),
        key: String,
        name: String,
        icon: String,
        requirement: String,
        unlockedAt: Date? = nil
    ) {
        self.id = id
        self.key = key
        self.name = name
        self.icon = icon
        self.requirement = requirement
        self.unlockedAt = unlockedAt
    }
}
