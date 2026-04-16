import SwiftUI

/// Coming-soon placeholder for the Subscriptions feature.
/// Pushed as a NavigationLink destination from HubView — inherits Hub's NavigationStack.
struct SubscriptionsPlaceholderView: View {
    private let features: [(label: String, icon: String)] = [
        ("Track recurring charges",         "repeat"),
        ("Link to your credit cards",       "creditcard.fill"),
        ("See total monthly spend",         "chart.bar.fill"),
        ("Match credits to subscriptions",  "checkmark.circle.fill")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // ── Hero ──────────────────────────────────────────────────────
                VStack(spacing: 14) {
                    Image(systemName: "repeat.circle")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        Text("Subscriptions")
                            .font(.title2.weight(.semibold))
                        Text("Coming soon to Hub")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 40)

                Divider()
                    .padding(.horizontal, 32)

                // ── Feature preview ───────────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    Text("What's coming")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    ForEach(features, id: \.label) { feature in
                        HStack(spacing: 14) {
                            Image(systemName: feature.icon)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.blue)
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
        .navigationTitle("Subscriptions")
    }
}

#Preview {
    NavigationStack {
        SubscriptionsPlaceholderView()
    }
}
