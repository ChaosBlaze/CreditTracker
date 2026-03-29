import SwiftUI
import SwiftData

struct CreditRowView: View {
    @Environment(\.modelContext) private var context
    let credit: Credit
    let card: Card

    @State private var showLogModal = false
    @State private var tapScale: CGFloat = 1.0
    @State private var claimHapticTrigger = false
    @State private var unclaimHapticTrigger = false

    private var activePeriod: PeriodLog? {
        PeriodEngine.activePeriodLog(for: credit)
    }
    private var startColor: Color { Color(hex: card.gradientStartHex) }
    private var endColor: Color { Color(hex: card.gradientEndHex) }

    private var fraction: Double { activePeriod?.fillFraction ?? 0 }

    var body: some View {
        Button {
            // Tap scale animation + haptic
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                tapScale = 0.97
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    tapScale = 1.0
                }
                showLogModal = true
            }
        } label: {
            HStack(spacing: 12) {
                // Chunky progress ring
                ChunkyProgressRing(
                    fraction: fraction,
                    gradientStart: startColor,
                    gradientEnd: endColor,
                    strokeWidth: 6,
                    size: 44
                )

                // Center column
                VStack(alignment: .leading, spacing: 3) {
                    Text(credit.name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)

                    if let period = activePeriod {
                        Text(period.periodLabel)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    // Dollar amount with accent color for claimed portion
                    if let period = activePeriod {
                        HStack(spacing: 0) {
                            Text("$\(Int(period.claimedAmount))")
                                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [startColor, endColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            Text(" / $\(Int(credit.totalValue))")
                                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        // Micro progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.white.opacity(0.08))
                                    .frame(height: 2)
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [startColor, endColor],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: min(geo.size.width, 40) * fraction, height: 2)
                            }
                        }
                        .frame(width: 40, height: 2)
                    }
                }

                Spacer()

                // Glass status pill
                if let period = activePeriod {
                    GlassStatusPill(status: period.periodStatus)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(tapScale)
        .sensoryFeedback(.impact(weight: .light), trigger: showLogModal)
        // Swipe actions
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                showLogModal = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if let period = activePeriod, period.periodStatus == .claimed {
                // Unclaim
                Button {
                    unclaimHapticTrigger.toggle()
                    period.claimedAmount = 0
                    period.periodStatus = .pending
                    try? context.save()
                    NotificationManager.shared.scheduleReminder(for: credit)
                } label: {
                    Label("Unclaim", systemImage: "arrow.uturn.backward")
                }
                .tint(.orange)
            } else {
                // Quick claim full amount
                Button {
                    claimHapticTrigger.toggle()
                    quickClaimFull()
                } label: {
                    Label("Claim", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: claimHapticTrigger)
        .sensoryFeedback(.impact(weight: .light), trigger: unclaimHapticTrigger)
        .sheet(isPresented: $showLogModal) {
            CreditLoggingView(credit: credit, card: card)
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
                .presentationBackground(.thinMaterial)
        }
    }

    private func quickClaimFull() {
        guard let period = activePeriod else { return }
        period.claimedAmount = credit.totalValue
        period.periodStatus = .claimed
        try? context.save()
        NotificationManager.shared.cancelReminder(for: credit)

        // Gamification
        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        _ = GamificationEngine.recordClaim(
            amount: credit.totalValue,
            credit: credit,
            cards: cards,
            context: context
        )
    }
}
