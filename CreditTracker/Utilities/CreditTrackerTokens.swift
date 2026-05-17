import SwiftUI

enum CT {
    // MARK: - Backgrounds
    static let background   = Color("CT/Background")
    static let surface      = Color("CT/Surface")
    static let surface2     = Color("CT/Surface2")

    // MARK: - Accent (terracotta)
    static let accent       = Color("CT/Accent")
    static let accentDeep   = Color("CT/AccentDeep")
    static let accentSoft   = Color("CT/AccentSoft")
    static let accentFaint  = Color("CT/AccentFaint")

    // MARK: - Ink (warm neutrals)
    static let ink          = Color("CT/Ink")
    static let ink2         = Color("CT/Ink2")
    static let ink3         = Color("CT/Ink3")
    static let ink4         = Color("CT/Ink4")

    // MARK: - Borders
    static let hairline     = Color("CT/Hairline")

    // MARK: - Semantic status
    static let done         = Color("CT/Done")
    static let doneBg       = Color("CT/DoneBg")
    static let partial      = Color("CT/Partial")
    static let partialBg    = Color("CT/PartialBg")
    static let urgent       = Color("CT/Urgent")
    static let urgentBg     = Color("CT/UrgentBg")
}

extension Font {
    // 56pt serif medium — hero unclaimed numeral
    static let ctHeroNumeral = Font.system(size: 56, weight: .medium, design: .serif)

    // 30pt serif regular — "$" prefix beside hero numeral
    static let ctDollarPrefix = Font.system(size: 30, weight: .regular, design: .serif)

    // caption2 monospaced — section eyebrows ("UNCLAIMED THIS MONTH")
    static let ctEyebrow = Font.system(.caption2, design: .monospaced)

    // caption monospaced — period labels, amounts, fee badges
    static let ctMeta = Font.system(.caption, design: .monospaced)

    // 11pt monospaced uppercase — section headers ("ALL CARDS", "EXPIRES SOON")
    static let ctSectionLabel = Font.system(size: 11, weight: .semibold, design: .monospaced)

    // subheadline semibold — card name in rows/blocks
    static let ctRowTitle = Font.subheadline.weight(.semibold)
}
