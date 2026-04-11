import Foundation
import SwiftData

@Model
final class BonusCard {
    var id: UUID = UUID()
    var cardName: String = ""
    var bonusAmount: String = ""
    var dateOpened: Date = Date()

    // Direct Deposit requirement
    var requiresDirectDeposit: Bool = false
    var directDepositTarget: Double = 0.0
    var currentDirectDepositAmount: Double = 0.0

    // Minimum spend / purchases requirement
    var requiresPurchases: Bool = false
    var purchaseTarget: Double = 0.0
    var currentPurchaseAmount: Double = 0.0

    // Catch-all "other" requirement
    var requiresOther: Bool = false
    var otherDescription: String = ""
    var isOtherCompleted: Bool = false

    var isCompleted: Bool = false

    // MARK: - QoL Fields (Phase 1)

    /// Who opened this card — useful in family/partner setups (e.g. "Shekar", "Wife").
    /// Defaults to empty string so existing SwiftData rows migrate safely without a schema version bump.
    var accountHolderName: String = ""

    /// Free-form notepad — account numbers, referral links, reminder details, etc.
    var miscNotes: String = ""

    // MARK: - Computed helpers

    var purchaseFraction: Double {
        guard requiresPurchases, purchaseTarget > 0 else { return 0 }
        return min(currentPurchaseAmount / purchaseTarget, 1.0)
    }

    var directDepositFraction: Double {
        guard requiresDirectDeposit, directDepositTarget > 0 else { return 0 }
        return min(currentDirectDepositAmount / directDepositTarget, 1.0)
    }

    /// True when every active requirement is satisfied
    var allRequirementsMet: Bool {
        let purchaseDone = !requiresPurchases || currentPurchaseAmount >= purchaseTarget
        let ddDone = !requiresDirectDeposit || currentDirectDepositAmount >= directDepositTarget
        let otherDone = !requiresOther || isOtherCompleted
        return purchaseDone && ddDone && otherDone
    }

    init(
        id: UUID = UUID(),
        cardName: String,
        bonusAmount: String,
        dateOpened: Date = Date()
    ) {
        self.id = id
        self.cardName = cardName
        self.bonusAmount = bonusAmount
        self.dateOpened = dateOpened
    }
}
