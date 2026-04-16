import SwiftUI

/// A single card application entry shown in the history list.
struct PlannerApplicationRow: View {
    let app: CardApplication

    var body: some View {
        HStack(spacing: 14) {
            // Issuer color swatch + type icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(issuerColor.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: app.cardTypeEnum.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(issuerColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(app.cardName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(app.issuer)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(app.cardTypeEnum.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                // Approved / Denied badge
                Text(app.isApproved ? "Approved" : "Denied")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(app.isApproved ? Color.green : Color.red, in: Capsule())

                // Relative age
                Text(app.relativeAgeLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var issuerColor: Color {
        guard let known = KnownIssuer(rawValue: app.issuer) else { return .secondary }
        return Color(hex: known.accentHex)
    }
}
