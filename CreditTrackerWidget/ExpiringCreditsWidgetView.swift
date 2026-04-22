import SwiftUI
import WidgetKit

struct ExpiringCreditsWidgetView: View {
    let entry: ExpiringCreditsEntry
    @Environment(\.widgetFamily) private var family

    // Tint the widget background with the most-urgent credit's card gradient
    private var backgroundColors: [Color] {
        guard let first = entry.items.first else {
            return [Color.green.opacity(0.14), Color.teal.opacity(0.07)]
        }
        return [
            Color(hex: first.gradientStartHex).opacity(0.16),
            Color(hex: first.gradientEndHex).opacity(0.08)
        ]
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:  smallView
            case .systemLarge:  largeView
            default:            mediumView
            }
        }
        .containerBackground(
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            for: .widget
        )
    }

    // MARK: - Small (single most-urgent credit)

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            widgetHeader(compact: true)

            Spacer()

            if let item = entry.items.first {
                // Large countdown number
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(item.daysRemaining == 0 ? "Today" : "\(item.daysRemaining)")
                        .font(.system(size: item.daysRemaining == 0 ? 28 : 44, weight: .bold, design: .rounded))
                        .foregroundStyle(urgencyColor(for: item.daysRemaining))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if item.daysRemaining > 0 {
                        Text("days")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(urgencyColor(for: item.daysRemaining).opacity(0.75))
                            .padding(.bottom, 5)
                    }
                }

                Text(item.creditName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(item.cardName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.bottom, 10)

                // Progress bar + remaining value
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.quaternary)
                                .frame(height: 4)
                            Capsule()
                                .fill(cardGradient(item))
                                .frame(width: max(4, geo.size.width * item.fillFraction), height: 4)
                        }
                    }
                    .frame(height: 4)

                    Text("$\(formatted(item.value * (1 - item.fillFraction))) remaining")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                smallEmptyState
            }
        }
        .padding(14)
    }

    // MARK: - Medium (2 credits as rows)

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 0) {
            widgetHeader(compact: false)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            if entry.isEmpty {
                Spacer()
                HStack { Spacer(); emptyStateContent; Spacer() }
                Spacer()
            } else {
                VStack(spacing: 7) {
                    ForEach(Array(entry.items.prefix(2))) { item in
                        compactCreditRow(item)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Large (3 credits with progress rings)

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 0) {
            widgetHeader(compact: false)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            if entry.isEmpty {
                Spacer()
                HStack { Spacer(); emptyStateContent; Spacer() }
                Spacer()
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(entry.items.prefix(3))) { item in
                        detailedCreditRow(item)
                    }
                }
                .padding(.horizontal, 14)

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Header

    private func widgetHeader(compact: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "clock.badge.exclamationmark.fill")
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Expiring Soon")
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if !compact && entry.items.count == 3 {
                Text("Top 3")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Compact Credit Row (medium widget)

    private func compactCreditRow(_ item: ExpiringCreditItem) -> some View {
        HStack(spacing: 10) {
            // Card color accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(cardGradient(item))
                .frame(width: 3, height: 40)

            // Credit info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.creditName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.cardName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Days badge + value
            VStack(alignment: .trailing, spacing: 2) {
                daysBadge(item)
                Text("$\(formatted(item.value))")
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Detailed Credit Row (large widget)

    private func detailedCreditRow(_ item: ExpiringCreditItem) -> some View {
        HStack(spacing: 12) {
            // Mini progress ring
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: item.fillFraction)
                    .stroke(cardGradient(item), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("$\(formatted(item.value))")
                    .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(4)
            }
            .frame(width: 44, height: 44)

            // Name + card + progress bar
            VStack(alignment: .leading, spacing: 3) {
                Text(item.creditName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.cardName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.quaternary)
                            .frame(height: 3)
                        Capsule()
                            .fill(cardGradient(item))
                            .frame(width: max(3, geo.size.width * item.fillFraction), height: 3)
                    }
                }
                .frame(height: 3)
            }

            Spacer()

            daysBadge(item)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Days Badge

    private func daysBadge(_ item: ExpiringCreditItem) -> some View {
        let color = urgencyColor(for: item.daysRemaining)
        return VStack(spacing: 0) {
            if item.daysRemaining == 0 {
                Text("Today")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            } else {
                Text("\(item.daysRemaining)")
                    .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                Text("days")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(color.opacity(0.7))
            }
        }
        .frame(minWidth: 38)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Empty States

    private var smallEmptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
            Text("All credits\nclaimed!")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var emptyStateContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            Text("No expiring credits")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text("All credits are claimed\nor up to date")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Helpers

    private func urgencyColor(for days: Int) -> Color {
        switch days {
        case 0...2: return .red
        case 3...6: return .orange
        case 7...13: return Color(hex: "#FF9F0A")
        default:    return .teal
        }
    }

    private func cardGradient(_ item: ExpiringCreditItem) -> LinearGradient {
        LinearGradient(
            colors: [Color(hex: item.gradientStartHex), Color(hex: item.gradientEndHex)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}

// MARK: - Widget definition

struct ExpiringCreditsWidget: Widget {
    let kind: String = "ExpiringCreditsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ExpiringCreditsProvider()) { entry in
            ExpiringCreditsWidgetView(entry: entry)
        }
        .configurationDisplayName("Expiring Credits")
        .description("See which credits expire soonest so you never leave money on the table.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    ExpiringCreditsWidget()
} timeline: {
    ExpiringCreditsEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    ExpiringCreditsWidget()
} timeline: {
    ExpiringCreditsEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    ExpiringCreditsWidget()
} timeline: {
    ExpiringCreditsEntry.placeholder
}

#Preview("Empty – Medium", as: .systemMedium) {
    ExpiringCreditsWidget()
} timeline: {
    ExpiringCreditsEntry(date: Date(), items: [])
}
