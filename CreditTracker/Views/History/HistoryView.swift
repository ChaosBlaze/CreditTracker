import SwiftUI
import Charts

// MARK: - HistoryView

struct HistoryView: View {
    @State private var viewModel = HistoryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    loadingState
                } else if let error = viewModel.errorMessage {
                    errorState(error)
                } else if viewModel.feedEntries.isEmpty {
                    emptyState
                } else {
                    feedContent
                }
            }
            .navigationTitle("History")
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.reload()
            }
        }
    }

    // MARK: - Feed Content

    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {

                // Phase 2 — ROI Dashboard
                HistoryROIDashboard(stats: viewModel.stats)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                // Phase 3 — Missed value callout (conditional)
                if viewModel.hasMissedEntries {
                    MissedValueCallout(
                        count:      viewModel.missedEntries.count,
                        totalValue: viewModel.totalMissedValue
                    )
                    .padding(.horizontal, 16)
                }

                // Section header
                HStack {
                    Text("Recent Activity")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(viewModel.feedEntries.count) entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Phase 3 — Activity feed
                ForEach(viewModel.feedEntries) { entry in
                    ActivityFeedRow(entry: entry)
                        .padding(.horizontal, 16)
                        // Infinite scroll: fire loadMore when the last row appears.
                        .onAppear {
                            if entry.id == viewModel.feedEntries.last?.id {
                                Task { await viewModel.loadMore() }
                            }
                        }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .padding(.vertical, 16)
                }

                Spacer(minLength: 24)
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Placeholder States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.2)
            Text("Loading history…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Couldn't Load History")
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Try Again") {
                Task { await viewModel.reload() }
            }
            .fontWeight(.semibold)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .glassEffect(in: Capsule())
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No History Yet")
                    .font(.title2.weight(.semibold))
                Text("Your period logs will appear here\nas you track your credits.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ROI Dashboard Card

/// The "Year in Review" executive summary card.
///
/// Accepts a `HistoryStats` value type so that when ROI aggregation moves to
/// Cloud Functions, only the production site in `HistoryViewModel.buildStats()`
/// changes — this view needs zero modification.
struct HistoryROIDashboard: View {
    let stats: HistoryStats

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {

            // ── Header ────────────────────────────────────────────────
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(currentYear) Year in Review")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Value extracted vs. annual fees")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: stats.isPositive
                      ? "arrow.up.circle.fill"
                      : "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(stats.isPositive ? Color.green : Color.red)
                .symbolEffect(.bounce, value: stats.isPositive)
            }

            // ── Hero Net ROI ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("NET ROI")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(stats.netROI >= 0 ? "+" : "−")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(stats.isPositive ? Color.green : Color.red)

                    Text("$\(String(format: "%.0f", abs(stats.netROI)))")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(stats.isPositive ? Color.green : Color.red)
                        .contentTransition(.numericText())
                }
            }

            // ── Stats Row ─────────────────────────────────────────────
            HStack(spacing: 0) {
                roiStatBlock(
                    title:  "Annual Fees",
                    value:  "$\(String(format: "%.0f", stats.totalFees))",
                    color:  .secondary,
                    icon:   "creditcard"
                )

                Divider()
                    .frame(height: 40)
                    .padding(.horizontal, 16)

                roiStatBlock(
                    title:  "Value Extracted",
                    value:  "$\(String(format: "%.0f", stats.totalExtracted))",
                    color:  stats.totalExtracted >= stats.totalFees ? .green : .orange,
                    icon:   "dollarsign.circle"
                )
            }

            // ── Swift Charts Bar Graph ────────────────────────────────
            if !stats.monthlyBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Monthly Value")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Chart(stats.monthlyBreakdown) { point in
                        BarMark(
                            x: .value("Month", point.label),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.green.opacity(0.9), Color.teal.opacity(0.7)],
                                startPoint: .bottom,
                                endPoint:   .top
                            )
                        )
                        .cornerRadius(5)
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("$\(Int(v))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                                .foregroundStyle(.secondary.opacity(0.3))
                        }
                    }
                    .frame(height: 120)
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("No value extracted yet this year")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .padding(20)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func roiStatBlock(title: String, value: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .labelStyle(.titleOnly)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Missed Value Callout

/// Callout banner shown when any of the fetched logs have a `.missed` status.
/// Draws attention to uncaptured value without being alarmist.
struct MissedValueCallout: View {
    let count: Int
    let totalValue: Double

    var body: some View {
        ZStack {
            // Red-orange tint bleeds through the glass surface
            LinearGradient(
                colors: [Color.red.opacity(0.18), Color.orange.opacity(0.10)],
                startPoint: .topLeading,
                endPoint:   .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 14) {
                // Icon badge
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: "dollarsign.arrow.circlepath")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.red)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Money Left on the Table")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(
                        "\(count) missed period\(count == 1 ? "" : "s") · $\(String(format: "%.0f", totalValue)) unclaimed"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.red.opacity(0.25), lineWidth: 1.5)
        }
    }
}

// MARK: - Activity Feed Row

/// A single row in the global chronological activity feed.
///
/// The card's gradient tints the glass surface from behind — the same visual
/// language used by `CardSectionView` on the Dashboard tab.
struct ActivityFeedRow: View {
    let entry: HistoryFeedEntry

    private var startColor: Color { Color(hex: entry.gradientStartHex) }
    private var endColor:   Color { Color(hex: entry.gradientEndHex)   }

    var body: some View {
        ZStack(alignment: .leading) {
            // Gradient tint layer — bleeds through the glass surface
            LinearGradient(
                colors: [startColor.opacity(0.28), endColor.opacity(0.14)],
                startPoint: .topLeading,
                endPoint:   .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 12) {
                // Card colour accent strip
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [startColor, endColor],
                            startPoint: .top,
                            endPoint:   .bottom
                        )
                    )
                    .frame(width: 4, height: 38)

                // Credit + card name
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.creditName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(entry.cardName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Period label + amount + status pill
                VStack(alignment: .trailing, spacing: 5) {
                    // Claimed amount — or em dash for zero
                    if entry.claimedAmount > 0 {
                        Text("$\(String(format: "%.0f", entry.claimedAmount))")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.primary)
                    } else {
                        Text("—")
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 6) {
                        Text(entry.periodLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        StatusPill(status: entry.status)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
}
