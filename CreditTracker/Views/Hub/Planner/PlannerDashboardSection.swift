import SwiftUI

/// The eligibility dashboard shown at the top of PlannerView.
/// Displays the Chase 5/24 gauge, issuer velocity pill grid, and a
/// next-drop-off callout when the user is at or over the 5/24 limit.
struct PlannerDashboardSection: View {
    let status524: Chase524Status
    let velocityStatuses: [VelocityRuleStatus]
    let hardInquiry: HardInquirySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            chase524Card
            issuerVelocityGrid
            hardInquiryCard
        }
    }

    // MARK: - Chase 5/24 Card

    private var chase524Card: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chase 5/24")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Personal cards from any issuer · last 24 months")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(status524.currentCount)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(gaugeColor)
                    Text("/ 5")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Segmented 5-block progress bar
            HStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(index < status524.currentCount ? gaugeColor : Color.secondary.opacity(0.20))
                        .frame(height: 8)
                        .animation(.spring(response: 0.4), value: status524.currentCount)
                }
            }

            // Summary label
            HStack(spacing: 6) {
                Image(systemName: status524.isEligible ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(gaugeColor)
                Text(status524.summaryLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(gaugeColor)
            }

            // Drop-off callout — shown only when at limit
            if !status524.isEligible, let dropDate = status524.nextDropOffDate {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: dropDate).day ?? 0
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Next card drops off in \(days) day\(days == 1 ? "" : "s") — \(dropDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(16)
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var gaugeColor: Color {
        switch status524.statusColor {
        case .green:  return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red:    return .red
        }
    }

    // MARK: - Issuer Velocity Grid

    private var issuerVelocityGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Issuer Rules")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            // Two-column grid of velocity pills
            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(velocityStatuses) { vs in
                    velocityPill(vs)
                }
            }
        }
    }

    @ViewBuilder
    private func velocityPill(_ vs: VelocityRuleStatus) -> some View {
        HStack(spacing: 8) {
            // Status dot
            Circle()
                .fill(vs.isEligible ? Color.green : Color.red)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(vs.pillLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !vs.isEligible, let days = vs.daysUntilEligible {
                    Text("\(days)d until eligible")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(vs.currentCount)/\(vs.rule.maxCount) used")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Hard Inquiry Card

    private var hardInquiryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hard Inquiries")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            HStack(spacing: 0) {
                inquiryCell(count: hardInquiry.last30Days,  label: "30d",  isLast: false)
                Divider().frame(height: 32)
                inquiryCell(count: hardInquiry.last90Days,  label: "90d",  isLast: false)
                Divider().frame(height: 32)
                inquiryCell(count: hardInquiry.last180Days, label: "180d", isLast: false)
                Divider().frame(height: 32)
                inquiryCell(count: hardInquiry.last365Days, label: "1yr",  isLast: true)
            }
            .padding(.vertical, 10)
            .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private func inquiryCell(count: Int, label: String, isLast: Bool) -> some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.title3.weight(.bold))
                .foregroundStyle(count == 0 ? .secondary : .primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
