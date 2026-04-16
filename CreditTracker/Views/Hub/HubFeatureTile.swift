import SwiftUI

/// A reusable glass tile used in HubView to represent a single feature.
/// Pass `isAvailable: false` for features that are not yet implemented —
/// the tile renders with a "Coming Soon" badge and reduced opacity.
struct HubFeatureTile: View {
    let title: String
    let systemImage: String
    let description: String
    let stat: String?
    let accentColor: Color
    let isAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(isAvailable ? accentColor : .secondary)
                .frame(width: 50, height: 50)
                .background(
                    (isAvailable ? accentColor : Color.secondary).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            Spacer().frame(height: 14)

            // Title
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer().frame(height: 4)

            // Description
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(minHeight: 14)

            // Stat pill (live) or "Coming Soon" badge (unavailable)
            if isAvailable, let stat {
                Text(stat)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accentColor)
            } else if !isAvailable {
                Text("Coming Soon")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.40), in: Capsule())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(isAvailable ? 1.0 : 0.72)
    }
}

#Preview {
    HStack(spacing: 16) {
        HubFeatureTile(
            title: "Bonuses",
            systemImage: "sparkles",
            description: "Track sign-up bonuses and minimum spend requirements.",
            stat: "3 active bonuses",
            accentColor: .yellow,
            isAvailable: true
        )
        HubFeatureTile(
            title: "Subscriptions",
            systemImage: "repeat",
            description: "Track recurring charges and link them to your cards.",
            stat: nil,
            accentColor: .blue,
            isAvailable: false
        )
    }
    .padding()
}
