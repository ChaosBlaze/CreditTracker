import Foundation

enum TimeframeType: String, CaseIterable, Codable {
    case monthly = "monthly"
    case quarterly = "quarterly"
    case semiAnnual = "semiAnnual"
    case annual = "annual"

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .semiAnnual: return "Semi-Annual"
        case .annual: return "Annual"
        }
    }

    var periodsPerYear: Int {
        switch self {
        case .monthly: return 12
        case .quarterly: return 4
        case .semiAnnual: return 2
        case .annual: return 1
        }
    }
}

enum PeriodStatus: String, CaseIterable, Codable {
    case pending = "pending"
    case claimed = "claimed"
    case partiallyClaimed = "partiallyClaimed"
    case missed = "missed"

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .claimed: return "Claimed"
        case .partiallyClaimed: return "Partial"
        case .missed: return "Missed"
        }
    }

    var pillColor: String {
        switch self {
        case .pending: return "#A0A0A0"
        case .claimed: return "#34C759"
        case .partiallyClaimed: return "#FF9F0A"
        case .missed: return "#FF3B30"
        }
    }
}

// MARK: - BillingCycle

enum BillingCycle: String, CaseIterable, Codable {
    case weekly     = "weekly"
    case monthly    = "monthly"
    case quarterly  = "quarterly"
    case semiAnnual = "semiAnnual"
    case annual     = "annual"

    var displayName: String {
        switch self {
        case .weekly:     return "Weekly"
        case .monthly:    return "Monthly"
        case .quarterly:  return "Quarterly"
        case .semiAnnual: return "Semi-Annual"
        case .annual:     return "Annual"
        }
    }

    /// Approximate monthly cost multiplier for totals display.
    nonisolated var monthlyMultiplier: Double {
        switch self {
        case .weekly:     return 52.0 / 12.0
        case .monthly:    return 1.0
        case .quarterly:  return 1.0 / 3.0
        case .semiAnnual: return 1.0 / 6.0
        case .annual:     return 1.0 / 12.0
        }
    }

    /// Calendar months to add per cycle (nil = use .weekOfYear instead).
    nonisolated var monthsPerCycle: Int? {
        switch self {
        case .weekly:     return nil
        case .monthly:    return 1
        case .quarterly:  return 3
        case .semiAnnual: return 6
        case .annual:     return 12
        }
    }
}

// MARK: - SubscriptionCategory

enum SubscriptionCategory: String, CaseIterable, Codable {
    case streaming    = "streaming"
    case music        = "music"
    case news         = "news"
    case gaming       = "gaming"
    case fitness      = "fitness"
    case food         = "food"
    case shopping     = "shopping"
    case productivity = "productivity"
    case cloud        = "cloud"
    case other        = "other"

    var displayName: String {
        switch self {
        case .streaming:    return "Streaming"
        case .music:        return "Music"
        case .news:         return "News"
        case .gaming:       return "Gaming"
        case .fitness:      return "Fitness"
        case .food:         return "Food & Dining"
        case .shopping:     return "Shopping"
        case .productivity: return "Productivity"
        case .cloud:        return "Cloud Storage"
        case .other:        return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .streaming:    return "play.tv.fill"
        case .music:        return "music.note"
        case .news:         return "newspaper.fill"
        case .gaming:       return "gamecontroller.fill"
        case .fitness:      return "figure.run"
        case .food:         return "fork.knife"
        case .shopping:     return "bag.fill"
        case .productivity: return "briefcase.fill"
        case .cloud:        return "icloud.fill"
        case .other:        return "tag.fill"
        }
    }

    var accentHex: String {
        switch self {
        case .streaming:    return "#E50914"
        case .music:        return "#1DB954"
        case .news:         return "#4A90D9"
        case .gaming:       return "#9B59B6"
        case .fitness:      return "#FF6B35"
        case .food:         return "#F39C12"
        case .shopping:     return "#E91E63"
        case .productivity: return "#0078D4"
        case .cloud:        return "#34AADC"
        case .other:        return "#8E8E93"
        }
    }
}

// MARK: - LoyaltyCategory

enum LoyaltyCategory: String, CaseIterable, Codable {
    case bankPoints = "bankPoints"
    case airline    = "airline"
    case hotel      = "hotel"
    case other      = "other"

    var displayName: String {
        switch self {
        case .bankPoints: return "Bank Points"
        case .airline:    return "Airline Miles"
        case .hotel:      return "Hotel Points"
        case .other:      return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .bankPoints: return "building.columns.fill"
        case .airline:    return "airplane"
        case .hotel:      return "bed.double.fill"
        case .other:      return "star.fill"
        }
    }
}
