import SwiftUI

struct HeroCardView: View {
    let unclaimedAmount: Double
    let totalAvailable: Double
    let claimedAmount: Double

    private var fraction: Double {
        guard totalAvailable > 0 else { return 0 }
        return min(claimedAmount / totalAvailable, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("UNCLAIMED THIS MONTH")
                .font(.ctEyebrow)
                .tracking(1.5)
                .foregroundStyle(CT.ink3)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("$")
                    .font(.ctDollarPrefix)
                    .foregroundStyle(CT.ink3)
                    .baselineOffset(14)

                Text("\(Int(unclaimedAmount))")
                    .font(.ctHeroNumeral)
                    .foregroundStyle(CT.ink)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.smooth(duration: 0.35), value: unclaimedAmount)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CT.surface2)
                    Capsule()
                        .fill(CT.accent)
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
            .padding(.top, 10)

            HStack(spacing: 6) {
                Text("$\(Int(claimedAmount)) claimed")
                    .font(.system(.caption, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(CT.accentFaint, in: Capsule())
                    .foregroundStyle(CT.accentDeep)

                Text("of $\(Int(totalAvailable)) available this period")
                    .font(.footnote)
                    .foregroundStyle(CT.ink2)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(CT.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(CT.hairline.opacity(0.6), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

#Preview {
    HeroCardView(unclaimedAmount: 45, totalAvailable: 120, claimedAmount: 75)
        .padding()
        .background(CT.background)
}
