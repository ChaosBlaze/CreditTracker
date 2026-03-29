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
