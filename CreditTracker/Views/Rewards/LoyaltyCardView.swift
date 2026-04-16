import SwiftUI
import SwiftData

// MARK: - LoyaltyCardView

/// A single row in the Rewards dashboard displaying one loyalty program.
///
/// Layout mirrors the mockup: circular icon on the left (brand logo when available,
/// gradient-initials fallback otherwise), program name and owner pill in the centre,
/// formatted balance badge on the right. Applies `.glassEffect` with a subtle
/// gradient wash tinting the glass from behind.
struct LoyaltyCardView: View {
    let program: LoyaltyProgram

    private var startColor: Color { Color(hex: program.gradientStartHex) }
    private var endColor:   Color { Color(hex: program.gradientEndHex) }

    /// Asset catalog name for the program logo — resolved by exact name match
    /// against the pre-built catalog. nil for custom / renamed programs.
    private var logoAssetName: String? {
        LoyaltyProgramTemplate.logoLookup[program.programName]
    }

    var body: some View {
        HStack(spacing: 14) {
            // ── Brand icon (logo or gradient-initials fallback) ────────────────
            ProgramIconView(
                initials:     programInitials,
                startColor:   startColor,
                endColor:     endColor,
                size:         44,
                logoAssetName: logoAssetName
            )

            // ── Program name + owner pill ──────────────────────────────────────
            VStack(alignment: .leading, spacing: 3) {
                Text(program.programName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !program.ownerName.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                        Text(program.ownerName)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }

            Spacer(minLength: 8)

            // ── Balance badge ──────────────────────────────────────────────────
            Text(program.pointBalance.formatted(.number))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            // Subtle gradient wash tints the glass from behind — lighter than
            // GlassCardContainer so dashboard rows stay visually calm in a list.
            LinearGradient(
                colors: [startColor.opacity(0.18), endColor.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Initials (used only when no logo is available)

    private var programInitials: String {
        let skip = Set(["the", "of", "and", "&", "miles", "points", "rewards",
                        "plus", "one", "air", "plan", "airlines", "airways"])
        let words = program.programName
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty && !skip.contains($0.lowercased()) }
        switch words.count {
        case 0: return "?"
        case 1: return String(words[0].prefix(2)).uppercased()
        default: return (String(words[0].prefix(1)) + String(words[1].prefix(1))).uppercased()
        }
    }
}

// MARK: - ProgramIconView

/// Reusable circular icon view used in both the Rewards dashboard rows and
/// the `ProgramPickerView` catalog list.
///
/// **Rendering logic:**
/// - If `logoAssetName` is provided AND the image exists in the asset catalog,
///   shows the brand logo on a white circle with subtle shadow — matching the
///   app-icon aesthetic in the mockups (IMG_5398–IMG_5403).
/// - Otherwise renders a gradient-filled circle with two-letter white initials
///   as a clean fallback.
struct ProgramIconView: View {
    let initials:      String
    let startColor:    Color
    let endColor:      Color
    var size:          CGFloat = 44
    var logoAssetName: String? = nil

    var body: some View {
        if let assetName = logoAssetName, UIImage(named: assetName) != nil {
            logoView(assetName: assetName)
        } else {
            gradientInitialsView
        }
    }

    // MARK: - Logo variant

    private func logoView(assetName: String) -> some View {
        ZStack {
            // White background circle — gives every logo a clean, consistent
            // iOS-app-icon appearance regardless of the image's own background.
            Circle()
                .fill(.white)

            Image(assetName)
                .resizable()
                .scaledToFit()
                // Padding keeps the logo from touching the circle edge.
                .padding(size * 0.14)
        }
        .frame(width: size, height: size)
        // Subtle shadow lifts the white circle off the glass background.
        .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
    }

    // MARK: - Gradient-initials fallback

    private var gradientInitialsView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [startColor, endColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials)
                .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
