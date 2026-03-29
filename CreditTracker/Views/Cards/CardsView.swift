import SwiftUI
import SwiftData

struct CardsView: View {
    @Query(sort: \Card.sortOrder) private var cards: [Card]
    @State private var selectedCard: Card? = nil

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    ContentUnavailableView(
                        "No Cards",
                        systemImage: "creditcard",
                        description: Text("Add a card from the Dashboard to set up payment reminders.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(cards) { card in
                                CardPaymentRow(card: card)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedCard = card
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("Cards")
            .sheet(item: $selectedCard) { card in
                CardPaymentDetailView(card: card)
            }
        }
    }
}

// MARK: - Card row

struct CardPaymentRow: View {
    let card: Card

    private var startColor: Color { Color(hex: card.gradientStartHex) }
    private var endColor: Color { Color(hex: card.gradientEndHex) }

    private var isDueSoon: Bool {
        guard let dueDay = card.paymentDueDay, card.paymentReminderEnabled else { return false }
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.component(.day, from: now)

        let daysUntilDue: Int
        if dueDay >= today {
            daysUntilDue = dueDay - today
        } else {
            let yearMonth = calendar.dateComponents([.year, .month], from: now)
            var comps = DateComponents()
            comps.year = yearMonth.year
            comps.month = (yearMonth.month ?? 1) + 1
            comps.day = dueDay
            guard let nextDue = calendar.date(from: comps) else { return false }
            daysUntilDue = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: nextDue).day ?? 0
        }

        return daysUntilDue <= card.paymentReminderDaysBefore
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [startColor.opacity(0.35), endColor.opacity(0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [startColor, endColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("$\(Int(card.annualFee))/yr")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        if isDueSoon {
                            PulsingDot()
                        }
                        if let dueDay = card.paymentDueDay {
                            Text("Due \(ordinal(dueDay))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(isDueSoon ? Color.orange : Color.secondary)
                        } else {
                            Text("No due date set")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: startColor.opacity(0.25), radius: 10, x: 0, y: 4)
    }

    private func ordinal(_ day: Int) -> String {
        switch day {
        case 11, 12, 13: return "\(day)th"
        case let n where n % 10 == 1: return "\(day)st"
        case let n where n % 10 == 2: return "\(day)nd"
        case let n where n % 10 == 3: return "\(day)rd"
        default: return "\(day)th"
        }
    }
}

// MARK: - Pulsing dot

struct PulsingDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: 8, height: 8)
            .scaleEffect(pulsing ? 1.4 : 1.0)
            .opacity(pulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}
