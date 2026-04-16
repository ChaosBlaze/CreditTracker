import Foundation

// MARK: - LoyaltyProgramTemplate

/// A pre-defined catalog entry for a known loyalty program.
/// Used to populate the searchable program picker and pre-fill gradient colors
/// when a user adds a new program. No SwiftData persistence — purely static data.
struct LoyaltyProgramTemplate: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let category: LoyaltyCategory
    let gradientStartHex: String
    let gradientEndHex: String

    /// Two-letter initials derived from significant words in the program name.
    /// Used as the icon label in the colored circle.
    var initials: String {
        let skip = Set(["the", "of", "and", "&", "miles", "points", "rewards",
                        "plus", "one", "air", "plan", "airlines", "airways"])
        let words = name
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty && !skip.contains($0.lowercased()) }
        switch words.count {
        case 0: return "?"
        case 1: return String(words[0].prefix(2)).uppercased()
        default: return (String(words[0].prefix(1)) + String(words[1].prefix(1))).uppercased()
        }
    }

    // Hashable — use id since UUID is already Hashable
    static func == (lhs: LoyaltyProgramTemplate, rhs: LoyaltyProgramTemplate) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Catalog

extension LoyaltyProgramTemplate {

    /// Full sorted catalog of US-focused loyalty programs across all categories.
    static let all: [LoyaltyProgramTemplate] = (bankPoints + airlineMiles + hotelPoints)
        .sorted { $0.name < $1.name }

    // MARK: Bank Points

    static let bankPoints: [LoyaltyProgramTemplate] = [
        .init(name: "Amex Membership Rewards",    category: .bankPoints, gradientStartHex: "#007BC0", gradientEndHex: "#2B9FD4"),
        .init(name: "Bank of America Points",      category: .bankPoints, gradientStartHex: "#CC0000", gradientEndHex: "#E31837"),
        .init(name: "Bilt Rewards",                category: .bankPoints, gradientStartHex: "#2C2C2C", gradientEndHex: "#484848"),
        .init(name: "Capital One Miles",           category: .bankPoints, gradientStartHex: "#C4122D", gradientEndHex: "#9E0E25"),
        .init(name: "Chase Ultimate Rewards",      category: .bankPoints, gradientStartHex: "#1A3A5C", gradientEndHex: "#274D78"),
        .init(name: "Citi ThankYou Points",        category: .bankPoints, gradientStartHex: "#003B80", gradientEndHex: "#004FA8"),
        .init(name: "Discover Miles",              category: .bankPoints, gradientStartHex: "#F4901D", gradientEndHex: "#E8700E"),
        .init(name: "Navy Federal Rewards",        category: .bankPoints, gradientStartHex: "#1B3A6A", gradientEndHex: "#142A4E"),
        .init(name: "US Bank Altitude Points",     category: .bankPoints, gradientStartHex: "#CF0022", gradientEndHex: "#A60019"),
        .init(name: "USAA Rewards",                category: .bankPoints, gradientStartHex: "#003087", gradientEndHex: "#00408B"),
        .init(name: "Wells Fargo Rewards",         category: .bankPoints, gradientStartHex: "#C8102E", gradientEndHex: "#A60D26"),
    ]

    // MARK: Airline Miles

    static let airlineMiles: [LoyaltyProgramTemplate] = [
        .init(name: "AA AAdvantage",               category: .airline, gradientStartHex: "#0078D2", gradientEndHex: "#004B99"),
        .init(name: "Aeroplan",                    category: .airline, gradientStartHex: "#B41F2A", gradientEndHex: "#7A0000"),
        .init(name: "Air France/KLM Flying Blue",  category: .airline, gradientStartHex: "#002157", gradientEndHex: "#001239"),
        .init(name: "Alaska Mileage Plan",         category: .airline, gradientStartHex: "#006EB6", gradientEndHex: "#004E8A"),
        .init(name: "British Airways Avios",       category: .airline, gradientStartHex: "#075AAA", gradientEndHex: "#003F7F"),
        .init(name: "Delta SkyMiles",              category: .airline, gradientStartHex: "#B40A14", gradientEndHex: "#7A0000"),
        .init(name: "Emirates Skywards",           category: .airline, gradientStartHex: "#BF0000", gradientEndHex: "#800000"),
        .init(name: "Frontier Miles",              category: .airline, gradientStartHex: "#00A651", gradientEndHex: "#007A3C"),
        .init(name: "Hawaiian Miles",              category: .airline, gradientStartHex: "#702083", gradientEndHex: "#4A1558"),
        .init(name: "JetBlue TrueBlue",            category: .airline, gradientStartHex: "#003876", gradientEndHex: "#00264E"),
        .init(name: "Singapore KrisFlyer",         category: .airline, gradientStartHex: "#F5A623", gradientEndHex: "#C47B00"),
        .init(name: "Southwest Rapid Rewards",     category: .airline, gradientStartHex: "#304CB2", gradientEndHex: "#1A2E7A"),
        .init(name: "Spirit Free Spirit",          category: .airline, gradientStartHex: "#DDB800", gradientEndHex: "#AA8C00"),
        .init(name: "United MileagePlus",          category: .airline, gradientStartHex: "#013984", gradientEndHex: "#001B5C"),
        .init(name: "Virgin Atlantic Flying Club", category: .airline, gradientStartHex: "#E70000", gradientEndHex: "#B30000"),
    ]

    // MARK: Hotel Points

    static let hotelPoints: [LoyaltyProgramTemplate] = [
        .init(name: "Best Western Rewards",  category: .hotel, gradientStartHex: "#003E8A", gradientEndHex: "#002B61"),
        .init(name: "Choice Privileges",     category: .hotel, gradientStartHex: "#F15A22", gradientEndHex: "#C04416"),
        .init(name: "Hilton Honors",         category: .hotel, gradientStartHex: "#004B8D", gradientEndHex: "#00337A"),
        .init(name: "IHG One Rewards",       category: .hotel, gradientStartHex: "#006BB8", gradientEndHex: "#00508A"),
        .init(name: "Marriott Bonvoy",       category: .hotel, gradientStartHex: "#2C2C72", gradientEndHex: "#1E1E56"),
        .init(name: "World of Hyatt",        category: .hotel, gradientStartHex: "#693F88", gradientEndHex: "#4A2C63"),
        .init(name: "Wyndham Rewards",       category: .hotel, gradientStartHex: "#004A97", gradientEndHex: "#003570"),
    ]
}
