import Foundation

// MARK: - PlannerEligibilityEngine
//
// Pure logic layer — no SwiftUI or SwiftData imports.
// All methods are static and work on plain [CardApplication] arrays
// so they are trivially testable without a model container.
//
// Terminology used throughout (matches r/churning / Doctor of Credit vocabulary):
//   5/24   – Chase rule: ≥5 personal cards from ANY issuer in 24 months = ineligible
//   SUB    – Sign-Up Bonus
//   velocity rule – per-issuer limit on how many cards per rolling time window

enum PlannerEligibilityEngine {

    // MARK: - Chase 5/24

    /// Number of 5/24-counting cards opened by `player` within the last 24 months.
    /// Only approved personal cards from any issuer count.
    static func chase524Count(
        player: String,
        applications: [CardApplication],
        referenceDate: Date = Date()
    ) -> Int {
        let cutoff = referenceDate.addingTimeInterval(-24 * 30.44 * 86400) // ~24 calendar months
        return applications.filter {
            $0.player == player &&
            $0.countsToward524 &&
            $0.applicationDate >= cutoff
        }.count
    }

    /// Status summary for Chase 5/24.
    static func chase524Status(
        player: String,
        applications: [CardApplication],
        referenceDate: Date = Date()
    ) -> Chase524Status {
        let count = chase524Count(player: player, applications: applications, referenceDate: referenceDate)
        let nextDrop = chase524NextDropOffDate(player: player, applications: applications, referenceDate: referenceDate)
        return Chase524Status(currentCount: count, maxAllowed: 5, nextDropOffDate: nextDrop)
    }

    /// Date when the oldest 5/24-counting card falls off the 24-month window,
    /// reducing the count by one. Returns nil if 0 cards currently count.
    static func chase524NextDropOffDate(
        player: String,
        applications: [CardApplication],
        referenceDate: Date = Date()
    ) -> Date? {
        let cutoff = referenceDate.addingTimeInterval(-24 * 30.44 * 86400)
        let counting = applications
            .filter { $0.player == player && $0.countsToward524 && $0.applicationDate >= cutoff }
            .sorted { $0.applicationDate < $1.applicationDate } // oldest first

        guard let oldest = counting.first else { return nil }

        // The card drops off exactly 24 calendar months after its application date.
        return Calendar.current.date(byAdding: .month, value: 24, to: oldest.applicationDate)
    }

    /// Date when the count will drop below 5 (i.e. Chase eligibility resumes).
    /// Returns nil if already under 5.
    static func chase524EligibilityResumesDate(
        player: String,
        applications: [CardApplication],
        referenceDate: Date = Date()
    ) -> Date? {
        let count = chase524Count(player: player, applications: applications, referenceDate: referenceDate)
        guard count >= 5 else { return nil }

        // Sort counting cards oldest-first; we need to drop (count - 4) cards
        // before we are back at 4/24, making us eligible for the next Chase card.
        let cutoff = referenceDate.addingTimeInterval(-24 * 30.44 * 86400)
        let counting = applications
            .filter { $0.player == player && $0.countsToward524 && $0.applicationDate >= cutoff }
            .sorted { $0.applicationDate < $1.applicationDate }

        let dropCount = count - 4   // need to shed this many to reach 4/24
        guard dropCount > 0, counting.count >= dropCount else { return nil }

        let targetCard = counting[dropCount - 1]
        return Calendar.current.date(byAdding: .month, value: 24, to: targetCard.applicationDate)
    }

    // MARK: - Issuer Velocity Rules

    /// Returns all velocity rule statuses for a given player, computed over the
    /// provided application list.
    static func allVelocityStatuses(
        player: String,
        applications: [CardApplication],
        referenceDate: Date = Date()
    ) -> [VelocityRuleStatus] {
        IssuerVelocityRule.all.map { rule in
            velocityStatus(
                rule: rule,
                player: player,
                applications: applications,
                referenceDate: referenceDate
            )
        }
    }

    /// Evaluates a single velocity rule for a player.
    static func velocityStatus(
        rule: IssuerVelocityRule,
        player: String,
        applications: [CardApplication],
        referenceDate: Date = Date()
    ) -> VelocityRuleStatus {
        let cutoff = referenceDate.addingTimeInterval(-Double(rule.windowDays) * 86400)

        let matching = applications.filter { app in
            app.player == player &&
            app.isApproved &&
            rule.appliesTo(app) &&
            app.applicationDate >= cutoff
        }

        let currentCount  = matching.count
        let isEligible    = currentCount < rule.maxCount
        let nextEligible  = nextEligibleDate(rule: rule, matching: matching, referenceDate: referenceDate)

        return VelocityRuleStatus(
            rule: rule,
            currentCount: currentCount,
            isEligible: isEligible,
            nextEligibleDate: isEligible ? nil : nextEligible
        )
    }

    /// Date when the oldest card in `matching` rolls out of `rule`'s window,
    /// dropping the count below the limit. Returns nil if already eligible.
    private static func nextEligibleDate(
        rule: IssuerVelocityRule,
        matching: [CardApplication],
        referenceDate: Date
    ) -> Date? {
        guard matching.count >= rule.maxCount else { return nil }

        // Sort oldest-first; need to shed (count - maxCount + 1) cards to become eligible.
        let sorted = matching.sorted { $0.applicationDate < $1.applicationDate }
        let dropCount = matching.count - rule.maxCount + 1
        guard dropCount > 0, sorted.count >= dropCount else { return nil }

        let targetCard = sorted[dropCount - 1]
        return targetCard.applicationDate.addingTimeInterval(Double(rule.windowDays) * 86400)
    }

    // MARK: - Hard Inquiry Summary

    static func hardInquirySummary(
        player: String,
        applications: [CardApplication],
        referenceDate: Date = Date()
    ) -> HardInquirySummary {
        func count(days: Int) -> Int {
            let cutoff = referenceDate.addingTimeInterval(-Double(days) * 86400)
            return applications.filter { $0.player == player && $0.applicationDate >= cutoff }.count
        }
        return HardInquirySummary(
            last30Days:  count(days: 30),
            last90Days:  count(days: 90),
            last180Days: count(days: 180),
            last365Days: count(days: 365)
        )
    }

    // MARK: - Application Filtering

    /// All applications for a player, sorted newest-first.
    static func applications(
        for player: String,
        from all: [CardApplication]
    ) -> [CardApplication] {
        all.filter { $0.player == player }
           .sorted { $0.applicationDate > $1.applicationDate }
    }
}

// MARK: - Result Types

struct Chase524Status {
    let currentCount: Int
    let maxAllowed: Int    // always 5
    let nextDropOffDate: Date?

    var isEligible: Bool { currentCount < maxAllowed }
    var slotsRemaining: Int { max(0, maxAllowed - currentCount) }

    var summaryLabel: String {
        if isEligible {
            return "\(slotsRemaining) slot\(slotsRemaining == 1 ? "" : "s") remaining"
        } else {
            if let date = nextDropOffDate {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
                return "Eligible in \(days) day\(days == 1 ? "" : "s")"
            }
            return "At limit"
        }
    }

    var statusColor: StatusColor {
        switch currentCount {
        case 0..<3: return .green
        case 3:     return .yellow
        case 4:     return .orange
        default:    return .red
        }
    }
}

struct VelocityRuleStatus: Identifiable {
    let rule: IssuerVelocityRule
    let currentCount: Int
    let isEligible: Bool
    let nextEligibleDate: Date?

    var id: String { rule.id }

    var pillLabel: String { "\(rule.issuer) \(rule.label)" }

    var daysUntilEligible: Int? {
        guard let date = nextEligibleDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: date).day
    }
}

struct HardInquirySummary {
    let last30Days:  Int
    let last90Days:  Int
    let last180Days: Int
    let last365Days: Int
}

enum StatusColor { case green, yellow, orange, red }

// MARK: - Velocity Rule Definitions

struct IssuerVelocityRule: Identifiable {
    let id: String          // e.g. "chase_2_30"
    let issuer: String      // e.g. "Chase"
    let label: String       // e.g. "2/30"
    let description: String // human-readable explanation
    let maxCount: Int       // max approved cards before rule triggers
    let windowDays: Int     // rolling window in days
    /// Which card types from this issuer count toward this rule.
    let countedTypes: Set<String>
    /// When true, cards from ALL issuers count (not just this issuer).
    /// Used for Chase 5/24 and Barclays 6/24.
    let allIssuers: Bool

    func appliesTo(_ app: CardApplication) -> Bool {
        if allIssuers {
            // Only personal cards count for cross-issuer rules (5/24, Barclays 6/24)
            return app.cardType == CardApplicationType.personal.rawValue
        }
        return app.issuer == issuer && countedTypes.contains(app.cardType)
    }

    // MARK: - Catalog

    static let all: [IssuerVelocityRule] = [

        // ── Chase ──────────────────────────────────────────────────────────────
        // 5/24 is handled separately in PlannerEligibilityEngine because it uses
        // countsToward524 logic (approved + personal only) and its own result type.
        IssuerVelocityRule(
            id: "chase_2_30",
            issuer: "Chase",
            label: "2/30",
            description: "Max 2 Chase cards approved in any 30-day window.",
            maxCount: 2,
            windowDays: 30,
            countedTypes: [CardApplicationType.personal.rawValue, CardApplicationType.business.rawValue],
            allIssuers: false
        ),

        // ── American Express ───────────────────────────────────────────────────
        IssuerVelocityRule(
            id: "amex_2_90",
            issuer: "Amex",
            label: "2/90",
            description: "Max 2 Amex credit cards (not charge cards) approved in 90 days.",
            maxCount: 2,
            windowDays: 90,
            countedTypes: [CardApplicationType.personal.rawValue, CardApplicationType.business.rawValue],
            allIssuers: false
        ),
        IssuerVelocityRule(
            id: "amex_1_5",
            issuer: "Amex",
            label: "1/5",
            description: "Max 1 Amex card approved in any 5-day window.",
            maxCount: 1,
            windowDays: 5,
            countedTypes: [CardApplicationType.personal.rawValue, CardApplicationType.business.rawValue,
                           CardApplicationType.charge.rawValue],
            allIssuers: false
        ),

        // ── Citi ───────────────────────────────────────────────────────────────
        IssuerVelocityRule(
            id: "citi_1_8",
            issuer: "Citi",
            label: "1/8",
            description: "Max 1 Citi card in any 8-day window.",
            maxCount: 1,
            windowDays: 8,
            countedTypes: [CardApplicationType.personal.rawValue, CardApplicationType.business.rawValue],
            allIssuers: false
        ),
        IssuerVelocityRule(
            id: "citi_2_65",
            issuer: "Citi",
            label: "2/65",
            description: "Max 2 Citi personal cards in any 65-day window.",
            maxCount: 2,
            windowDays: 65,
            countedTypes: [CardApplicationType.personal.rawValue],
            allIssuers: false
        ),

        // ── Bank of America ────────────────────────────────────────────────────
        IssuerVelocityRule(
            id: "boa_2_30",
            issuer: "Bank of America",
            label: "2/30",
            description: "Max 2 BofA cards in 30 days.",
            maxCount: 2,
            windowDays: 30,
            countedTypes: [CardApplicationType.personal.rawValue, CardApplicationType.business.rawValue],
            allIssuers: false
        ),
        IssuerVelocityRule(
            id: "boa_3_12",
            issuer: "Bank of America",
            label: "3/12",
            description: "Max 3 BofA cards in 12 months.",
            maxCount: 3,
            windowDays: 365,
            countedTypes: [CardApplicationType.personal.rawValue, CardApplicationType.business.rawValue],
            allIssuers: false
        ),
        IssuerVelocityRule(
            id: "boa_4_24",
            issuer: "Bank of America",
            label: "4/24",
            description: "Max 4 BofA cards in 24 months (the 2/3/4 rule).",
            maxCount: 4,
            windowDays: 730,
            countedTypes: [CardApplicationType.personal.rawValue, CardApplicationType.business.rawValue],
            allIssuers: false
        ),

        // ── Capital One ────────────────────────────────────────────────────────
        IssuerVelocityRule(
            id: "capone_1_6",
            issuer: "Capital One",
            label: "1/6",
            description: "Max 1 Capital One card approved in any 6-month window.",
            maxCount: 1,
            windowDays: 180,
            countedTypes: [CardApplicationType.personal.rawValue, CardApplicationType.business.rawValue],
            allIssuers: false
        ),

        // ── Barclays ───────────────────────────────────────────────────────────
        IssuerVelocityRule(
            id: "barclays_6_24",
            issuer: "Barclays",
            label: "6/24",
            description: "Barclays typically declines if you have 6+ new personal accounts (any issuer) in 24 months.",
            maxCount: 6,
            windowDays: 730,
            countedTypes: [CardApplicationType.personal.rawValue],
            allIssuers: true   // counts cards from ALL issuers
        ),

        // ── Wells Fargo ────────────────────────────────────────────────────────
        IssuerVelocityRule(
            id: "wf_1_6",
            issuer: "Wells Fargo",
            label: "1/6",
            description: "Max 1 Wells Fargo card in any 6-month window.",
            maxCount: 1,
            windowDays: 180,
            countedTypes: [CardApplicationType.personal.rawValue],
            allIssuers: false
        ),

        // ── US Bank ────────────────────────────────────────────────────────────
        IssuerVelocityRule(
            id: "usbank_2_12",
            issuer: "US Bank",
            label: "2/12",
            description: "Max 2 US Bank cards in any 12-month window.",
            maxCount: 2,
            windowDays: 365,
            countedTypes: [CardApplicationType.personal.rawValue, CardApplicationType.business.rawValue],
            allIssuers: false
        ),
    ]
}
