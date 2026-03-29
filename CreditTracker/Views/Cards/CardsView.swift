import SwiftUI
import SwiftData

struct CardsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Card.sortOrder) private var cards: [Card]
    @State private var selectedCard: Card? = nil
    @State private var showAddCard = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(cards) { card in
                        CardTileView(card: card)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedCard = card
                            }
                    }
                    .onMove { from, to in
                        reorderCards(from: from, to: to)
                    }

                    // Add Card button (dashed outline)
                    addCardButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(hex: "#0A0A0F"))
            .navigationTitle("Cards")
            .sheet(item: $selectedCard) { card in
                CardPaymentDetailView(card: card)
            }
            .sheet(isPresented: $showAddCard) {
                AddCardView()
            }
        }
    }

    private var addCardButton: some View {
        Button {
            showAddCard = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Add Card")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                    )
                    .foregroundStyle(.secondary.opacity(0.3))
            }
        }
        .buttonStyle(.plain)
    }

    private func reorderCards(from: IndexSet, to: Int) {
        var ordered = Array(cards)
        ordered.move(fromOffsets: from, toOffset: to)
        for (index, card) in ordered.enumerated() {
            card.sortOrder = index
        }
        try? context.save()
    }
}

// MARK: - Card Tile View

struct CardTileView: View {
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

    // Credit status dots
    private var creditDots: [(Color, Bool)] {
        card.credits.sorted { $0.name < $1.name }.map { credit in
            guard let period = PeriodEngine.activePeriodLog(for: credit) else {
                return (Color.gray, false)
            }
            switch period.periodStatus {
            case .claimed:
                return (startColor, true) // filled
            case .partiallyClaimed:
                return (startColor, true)
            case .missed:
                return (.red, true)
            case .pending:
                return (Color.gray.opacity(0.4), false) // hollow
            }
        }
    }

    var body: some View {
        AtmosphericCardView(
            gradientStart: startColor,
            gradientEnd: endColor,
            gradientOpacity: 0.25
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    // Left column
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.name)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("$\(Int(card.annualFee))/yr")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Right column: due date
                    VStack(alignment: .trailing, spacing: 4) {
                        if let dueDay = card.paymentDueDay {
                            HStack(spacing: 4) {
                                if isDueSoon {
                                    PulsingDot()
                                }
                                Image(systemName: "calendar")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text("Due \(ordinal(dueDay))")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(isDueSoon ? .orange : .secondary)
                            }
                        } else {
                            Text("Set date")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(startColor)
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Bottom: credit status dots
                if !creditDots.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(creditDots.enumerated()), id: \.offset) { _, dot in
                            Circle()
                                .fill(dot.0)
                                .frame(width: 6, height: 6)
                                .opacity(dot.1 ? 1.0 : 0.4)
                        }
                        Spacer()
                    }
                }
            }
        }
        .parallaxEffect(magnitude: 3)
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
