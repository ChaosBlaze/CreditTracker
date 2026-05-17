import SwiftUI

struct SegmentPipRow: View {
    let credits: [Credit]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(credits) { credit in
                RoundedRectangle(cornerRadius: 2)
                    .fill(pipColor(for: credit))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func pipColor(for credit: Credit) -> Color {
        guard let log = PeriodEngine.activePeriodLog(for: credit) else {
            return CT.ink4
        }
        switch log.periodStatus {
        case .claimed:
            return CT.done
        case .partiallyClaimed:
            return CT.partial
        case .pending:
            return log.daysUntilEnd <= 4 ? CT.urgent : CT.ink4
        case .missed:
            return CT.ink4
        }
    }
}

#Preview {
    SegmentPipRow(credits: [])
        .padding()
        .background(CT.background)
}
