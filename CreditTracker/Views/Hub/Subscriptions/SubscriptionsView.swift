import SwiftUI
import SwiftData

// MARK: - SubscriptionsView

/// Main subscriptions list — pushed as a NavigationLink destination from HubView.
/// Inherits Hub's NavigationStack; does NOT create its own.
struct SubscriptionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Subscription.nextBillingDate) private var allSubscriptions: [Subscription]
    @Query private var cards: [Card]

    @State private var showAddSheet = false
    @State private var selectedSubscription: Subscription?

    // MARK: - Derived

    private var activeSubscriptions: [Subscription] {
        allSubscriptions.filter { $0.isActive }
    }

    private var inactiveSubscriptions: [Subscription] {
        allSubscriptions.filter { !$0.isActive }
    }

    private var totalMonthlyCost: Double {
        activeSubscriptions.reduce(0) { $0 + $1.monthlyCost }
    }

    /// Monthly cost minus the monthly value of any linked statement credits.
    private var netMonthlyCost: Double {
        let allCredits = cards.flatMap { $0.credits }
        let creditIndex = Dictionary(uniqueKeysWithValues: allCredits.map { ($0.id.uuidString, $0) })

        let offset = activeSubscriptions.compactMap { sub -> Double? in
            guard !sub.linkedCreditID.isEmpty,
                  let credit = creditIndex[sub.linkedCreditID] else { return nil }
            let periodsPerYear = Double(credit.timeframeType.periodsPerYear)
            let creditMonthly = (periodsPerYear > 0) ? (credit.totalValue * periodsPerYear / 12.0) : credit.totalValue
            return min(sub.monthlyCost, creditMonthly)
        }.reduce(0, +)

        return max(0, totalMonthlyCost - offset)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !allSubscriptions.isEmpty {
                    summaryCard
                }

                if allSubscriptions.isEmpty {
                    emptyState
                } else {
                    subscriptionsList
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("Subscriptions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddSubscriptionView()
        }
        .sheet(item: $selectedSubscription) { sub in
            EditSubscriptionView(subscription: sub)
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Monthly Spend")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("$\(totalMonthlyCost, format: .number.precision(.fractionLength(2)))")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().frame(height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text("Net After Credits")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("$\(netMonthlyCost, format: .number.precision(.fractionLength(2)))")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(netMonthlyCost < totalMonthlyCost ? .green : .primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)

            Divider().frame(height: 40)

            VStack(alignment: .center, spacing: 4) {
                Text("Active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(activeSubscriptions.count)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 56)
            .padding(.leading, 16)
        }
        .padding(16)
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Subscriptions List

    private var subscriptionsList: some View {
        VStack(spacing: 12) {
            if !activeSubscriptions.isEmpty {
                sectionHeader("Active (\(activeSubscriptions.count))", systemImage: "checkmark.circle.fill", color: .green)
                ForEach(activeSubscriptions) { sub in
                    SubscriptionRow(subscription: sub, cards: cards)
                        .onTapGesture { selectedSubscription = sub }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteSubscription(sub)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                toggleActive(sub)
                            } label: {
                                Label("Pause", systemImage: "pause.circle.fill")
                            }
                            .tint(.orange)
                        }
                }
            }

            if !inactiveSubscriptions.isEmpty {
                sectionHeader("Inactive", systemImage: "pause.circle", color: .secondary)
                ForEach(inactiveSubscriptions) { sub in
                    SubscriptionRow(subscription: sub, cards: cards)
                        .opacity(0.6)
                        .onTapGesture { selectedSubscription = sub }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteSubscription(sub)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                toggleActive(sub)
                            } label: {
                                Label("Resume", systemImage: "play.circle.fill")
                            }
                            .tint(.green)
                        }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "repeat.circle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Subscriptions Yet")
                    .font(.title3.weight(.semibold))
                Text("Track recurring charges, link them to your cards, and see which credits offset the cost.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showAddSheet = true
            } label: {
                Label("Add Subscription", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
        }
        .padding(.top, 40)
        .padding(.horizontal, 24)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }

    private func deleteSubscription(_ sub: Subscription) {
        NotificationManager.shared.cancelSubscriptionReminder(for: sub)
        let docID = sub.syncID
        Task { await FirestoreSyncService.shared.deleteDocument(for: Subscription.self, id: docID) }
        context.delete(sub)
        try? context.save()
    }

    private func toggleActive(_ sub: Subscription) {
        sub.isActive.toggle()
        if sub.isActive {
            NotificationManager.shared.scheduleSubscriptionReminder(for: sub)
        } else {
            NotificationManager.shared.cancelSubscriptionReminder(for: sub)
        }
        try? context.save()
        Task { await FirestoreSyncService.shared.upload(sub) }
    }
}

// MARK: - SubscriptionRow

struct SubscriptionRow: View {
    let subscription: Subscription
    let cards: [Card]

    private var linkedCard: Card? {
        guard !subscription.linkedCardID.isEmpty else { return nil }
        return cards.first { $0.id.uuidString == subscription.linkedCardID }
    }

    private var linkedCredit: Credit? {
        guard !subscription.linkedCreditID.isEmpty else { return nil }
        return cards.flatMap { $0.credits }.first { $0.id.uuidString == subscription.linkedCreditID }
    }

    private var renewalLabel: String {
        let days = subscription.daysUntilRenewal
        switch days {
        case 0:  return "Today"
        case 1:  return "Tomorrow"
        default: return "\(days)d"
        }
    }

    private var renewalColor: Color {
        switch subscription.daysUntilRenewal {
        case 0...3:  return .red
        case 4...7:  return .orange
        default:     return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Category icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: subscription.categoryType.accentHex).opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: subscription.categoryType.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: subscription.categoryType.accentHex))
            }

            // Name and card
            VStack(alignment: .leading, spacing: 3) {
                Text(subscription.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let card = linkedCard {
                        Text(card.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(subscription.billingCycleType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Cost and renewal
            VStack(alignment: .trailing, spacing: 3) {
                Text("$\(subscription.cost, format: .number.precision(.fractionLength(2)))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .monospacedDigit()

                Text(renewalLabel)
                    .font(.caption2)
                    .foregroundStyle(renewalColor)

                if linkedCredit != nil {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text("Covered")
                            .font(.caption2)
                    }
                    .foregroundStyle(.green)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        SubscriptionsView()
    }
    .modelContainer(for: [Subscription.self, Card.self, Credit.self], inMemory: true)
}
