import SwiftUI
import SwiftData

// MARK: - LoyaltyCardView

/// A single row in the Rewards dashboard displaying one loyalty program.
///
/// Layout mirrors the mockup: gradient icon circle on the left, program name
/// and owner pill in the centre, formatted balance badge on the right.
/// Applies `.glassEffect` so the row sits naturally in the Liquid Glass list.
struct LoyaltyCardView: View {
    let program: LoyaltyProgram

    private var startColor: Color { Color(hex: program.gradientStartHex) }
    private var endColor:   Color { Color(hex: program.gradientEndHex) }

    var body: some View {
        HStack(spacing: 14) {
            // ── Gradient icon circle ───────────────────────────────────────────
            ProgramIconView(
                initials: programInitials,
                startColor: startColor,
                endColor: endColor,
                size: 44
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
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            // Subtle gradient wash tints the glass from behind — same technique
            // as GlassCardContainer but lighter so rows stay visually calm.
            LinearGradient(
                colors: [startColor.opacity(0.18), endColor.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Initials

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

/// Reusable gradient circle with white initials text.
/// Used in both `LoyaltyCardView` rows and the `ProgramPickerView` catalog list.
struct ProgramIconView: View {
    let initials:   String
    let startColor: Color
    let endColor:   Color
    var size: CGFloat = 44

    var body: some View {
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
