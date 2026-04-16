import Foundation
import SwiftData

// MARK: - CardApplication

/// Records a single credit card application event.
///
/// Used by the Card Planner feature to compute Chase 5/24 status,
/// per-issuer velocity rule compliance, and bonus cooldown windows.
///
/// ## P1 / P2
/// The `player` field stores `"P1"` or `"P2"` to support two-person family
/// tracking. All eligibility calculations are scoped to a single player.
///
/// ## Card Types
/// - **personal** – counts toward Chase 5/24 and most personal-card velocity rules.
/// - **business** – does NOT count toward Chase 5/24 (doesn't appear on personal
///   credit report for most issuers). Does count toward issuer-specific business rules.
/// - **charge** – Amex charge cards (Platinum, Gold, Green) do NOT count toward
///   Amex's 2/90 personal credit card velocity rule.
@Model
final class CardApplication {

    // MARK: - Core Fields

    var id: UUID = UUID()

    /// Display name of the card (e.g. "Chase Sapphire Preferred").
    var cardName: String = ""

    /// Issuer name, normalized to a known key for rule lookups.
    /// Use `Issuer.allCases` values (e.g. "Chase", "Amex", "Citi").
    var issuer: String = ""

    /// Raw value of `CardApplicationType` enum ("personal" / "business" / "charge").
    var cardType: String = CardApplicationType.personal.rawValue

    /// Date the application was submitted. Used for all rolling-window calculations.
    var applicationDate: Date = Date()

    /// Whether the application was approved. Denied applications still consume a
    /// hard inquiry but do NOT count toward 5/24 or velocity card counts.
    var isApproved: Bool = true

    /// Which person in the family this application belongs to.
    /// "P1" or "P2". Drives the top-right toggle in PlannerView.
    var player: String = "P1"

    /// Optional approved credit limit (for reference only, not used in calculations).
    var creditLimit: Double = 0.0

    /// Annual fee on the card (for reference; mirrors the annualFee on the linked Card
    /// if one exists, but this record stands alone).
    var annualFee: Double = 0.0

    /// Free-form notes: targeted offer, NLL status, referral links, account numbers, etc.
    var notes: String = ""

    // MARK: - Init

    init(
        id: UUID = UUID(),
        cardName: String,
        issuer: String,
        cardType: CardApplicationType = .personal,
        applicationDate: Date = Date(),
        isApproved: Bool = true,
        player: String = "P1",
        creditLimit: Double = 0.0,
        annualFee: Double = 0.0,
        notes: String = ""
    ) {
        self.id              = id
        self.cardName        = cardName
        self.issuer          = issuer
        self.cardType        = cardType.rawValue
        self.applicationDate = applicationDate
        self.isApproved      = isApproved
        self.player          = player
        self.creditLimit     = creditLimit
        self.annualFee       = annualFee
        self.notes           = notes
    }

    // MARK: - Computed Helpers

    var cardTypeEnum: CardApplicationType {
        CardApplicationType(rawValue: cardType) ?? .personal
    }

    /// True when this application counts toward Chase 5/24.
    /// Only approved personal cards from any issuer count.
    var countsToward524: Bool {
        isApproved && cardTypeEnum == .personal
    }

    /// Human-readable time since application (e.g. "45 days ago", "14 months ago").
    var relativeAgeLabel: String {
        let days = Calendar.current.dateComponents(
            [.day], from: applicationDate, to: Date()
        ).day ?? 0
        if days < 1   { return "Today" }
        if days == 1  { return "1 day ago" }
        if days < 30  { return "\(days) days ago" }
        let months = days / 30
        if months == 1 { return "1 month ago" }
        if months < 12 { return "\(months) months ago" }
        let years = months / 12
        return years == 1 ? "1 year ago" : "\(years) years ago"
    }
}

// MARK: - CardApplicationType

enum CardApplicationType: String, CaseIterable, Codable {
    case personal = "personal"
    case business = "business"
    case charge   = "charge"

    var displayName: String {
        switch self {
        case .personal: return "Personal"
        case .business: return "Business"
        case .charge:   return "Charge"
        }
    }

    var systemImage: String {
        switch self {
        case .personal: return "person.fill"
        case .business: return "briefcase.fill"
        case .charge:   return "bolt.fill"
        }
    }
}

// MARK: - Issuer Catalog

/// Known issuer names used as canonical identifiers throughout the Planner feature.
/// Values must match the `issuer` field stored on `CardApplication`.
enum KnownIssuer: String, CaseIterable {
    case chase         = "Chase"
    case amex          = "Amex"
    case citi          = "Citi"
    case bankOfAmerica = "Bank of America"
    case capitalOne    = "Capital One"
    case barclays      = "Barclays"
    case wellsFargo    = "Wells Fargo"
    case usBank        = "US Bank"
    case discover      = "Discover"
    case other         = "Other"

    /// Accent color hex used for issuer pills in the dashboard.
    var accentHex: String {
        switch self {
        case .chase:         return "#003087"   // Chase blue
        case .amex:          return "#007BC1"   // Amex blue
        case .citi:          return "#CC0000"   // Citi red
        case .bankOfAmerica: return "#E31837"   // BofA red
        case .capitalOne:    return "#D03027"   // CapOne red
        case .barclays:      return "#00AEEF"   // Barclays cyan
        case .wellsFargo:    return "#D71E28"   // WF red
        case .usBank:        return "#002776"   // USB navy
        case .discover:      return "#F76500"   // Discover orange
        case .other:         return "#888888"
        }
    }
}
