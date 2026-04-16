import SwiftUI

/// Coming-soon placeholder for the Card Planner feature.
/// Pushed as a NavigationLink destination from HubView — inherits Hub's NavigationStack.
///
/// Card Planner tracks:
///   • Chase 5/24 status (personal cards opened in last 24 months)
///   • Issuer velocity rules (Amex 2/90, Citi 2/65, BofA 2/3/4, Capital One 1/6, etc.)
///   • Bonus cooldown windows per card (when you're eligible for a SUB again)
///   • Hard inquiry timeline
///   • Application planning — next eligible date projections per issuer
struct PlannerPlaceholderView: View {
    private let features: [(label: String, icon: String)] = [
        ("5/24 dashboard — Chase eligibility at a glance",       "shield.lefthalf.filled"),
        ("Issuer velocity rules — Amex, Citi, BoA, Cap One & more", "building.2.fill"),
        ("Bonus cooldown windows — know when you're eligible again", "clock.arrow.circlepath"),
        ("Hard inquiry tracker — monitor credit pull activity",   "magnifyingglass.circle.fill"),
        ("Application planner — schedule your next card strategically", "calendar.badge.plus")
    ]

    // Static mock data for the eligibility preview card
    private let mockApps: [(name: String, daysAgo: Int)] = [
        ("Chase Sapphire Preferred",  45),
        ("Amex Gold",                120),
        ("Citi Strata Premier",      280),
    ]
    private let mock524Count = 3

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {

                // ── Hero ──────────────────────────────────────────────────────
                VStack(spacing: 14) {
                    Image(systemName: "creditcard.and.123")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        Text("Card Planner")
                            .font(.title2.weight(.semibold))
                        Text("Coming soon to Hub")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 40)

                Divider()
                    .padding(.horizontal, 32)

                // ── Eligibility preview (mock UI) ─────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your eligibility, at a glance")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    // Mock 5/24 status card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Chase 5/24")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Personal cards · last 24 months")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                Text("\(mock524Count)")
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.green)
                                Text("/ 5")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Segmented 5-block progress bar
                        HStack(spacing: 5) {
                            ForEach(0..<5, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(index < mock524Count ? Color.green : Color.secondary.opacity(0.22))
                                    .frame(height: 7)
                            }
                        }

                        Text("2 slots remaining — eligible for most Chase cards")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    .padding(14)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // Issuer rule pills row
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(issuerPills, id: \.label) { pill in
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(pill.color)
                                        .frame(width: 7, height: 7)
                                    Text(pill.label)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.primary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .glassEffect(in: Capsule())
                            }
                        }
                        .padding(.horizontal, 1) // prevent clipping
                    }

                    // Recent applications mini-list
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent applications")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)

                        ForEach(mockApps, id: \.name) { app in
                            HStack {
                                Image(systemName: "creditcard.fill")
                                    .font(.caption)
                                    .foregroundStyle(.purple)
                                Text(app.name)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(app.daysAgo)d ago")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }

                Divider()
                    .padding(.horizontal, 32)

                // ── Feature list ──────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    Text("What's coming")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    ForEach(features, id: \.label) { feature in
                        HStack(spacing: 14) {
                            Image(systemName: feature.icon)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.purple)
                                .frame(width: 28)

                            Text(feature.label)
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            Spacer()
                        }
                        .padding(14)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                // ── Stay tuned ────────────────────────────────────────────────
                Text("Stay tuned")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .glassEffect(in: Capsule())
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .navigationTitle("Card Planner")
    }

    // MARK: - Issuer Pill Data

    private struct IssuerPill {
        let label: String
        let color: Color
    }

    private var issuerPills: [IssuerPill] { [
        IssuerPill(label: "Chase 2/30",   color: .blue),
        IssuerPill(label: "Amex 2/90",    color: .green),
        IssuerPill(label: "Citi 2/65",    color: .orange),
        IssuerPill(label: "BoA 2/3/4",    color: .red),
        IssuerPill(label: "Cap One 1/6",  color: .purple),
        IssuerPill(label: "Barclays 6/24", color: .cyan),
        IssuerPill(label: "WF 1/6",       color: .yellow),
        IssuerPill(label: "US Bank 2/12", color: .mint),
    ] }
}

#Preview {
    NavigationStack {
        PlannerPlaceholderView()
    }
}
