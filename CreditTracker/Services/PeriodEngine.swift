import Foundation
import SwiftData

struct PeriodWindow {
    let label: String
    let start: Date
    let end: Date
}

struct PeriodEngine {

    // MARK: - Current Period Calculation

    static func currentPeriod(for credit: Credit, referenceDate: Date = Date()) -> PeriodWindow {
        switch credit.timeframeType {
        case .monthly:
            return PeriodWindow(
                label: DateHelpers.monthLabel(for: referenceDate),
                start: DateHelpers.startOfMonth(for: referenceDate),
                end: DateHelpers.endOfMonth(for: referenceDate)
            )
        case .quarterly:
            return PeriodWindow(
                label: DateHelpers.quarterLabel(for: referenceDate),
                start: DateHelpers.startOfQuarter(for: referenceDate),
                end: DateHelpers.endOfQuarter(for: referenceDate)
            )
        case .semiAnnual:
            return PeriodWindow(
                label: DateHelpers.halfYearLabel(for: referenceDate),
                start: DateHelpers.startOfHalfYear(for: referenceDate),
                end: DateHelpers.endOfHalfYear(for: referenceDate)
            )
        case .annual:
            return PeriodWindow(
                label: DateHelpers.yearLabel(for: referenceDate),
                start: DateHelpers.startOfYear(for: referenceDate),
                end: DateHelpers.endOfYear(for: referenceDate)
            )
        }
    }

    // MARK: - Period Advancement

    static func nextPeriodStart(after periodEnd: Date, timeframe: TimeframeType) -> Date {
        switch timeframe {
        case .monthly:
            return DateHelpers.calendar.date(byAdding: .second, value: 1, to: periodEnd)!
        case .quarterly:
            return DateHelpers.calendar.date(byAdding: .second, value: 1, to: periodEnd)!
        case .semiAnnual:
            return DateHelpers.calendar.date(byAdding: .second, value: 1, to: periodEnd)!
        case .annual:
            return DateHelpers.calendar.date(byAdding: .second, value: 1, to: periodEnd)!
        }
    }

    // MARK: - Ensure Current Period Exists (Idempotent)

    @discardableResult
    static func ensureCurrentPeriodExists(for credit: Credit, now: Date = Date(), context: ModelContext) -> PeriodLog {
        let currentWindow = currentPeriod(for: credit, referenceDate: now)

        if let existing = credit.periodLogs.first(where: { $0.periodLabel == currentWindow.label }) {
            return existing
        }

        let log = PeriodLog(
            periodLabel: currentWindow.label,
            periodStart: currentWindow.start,
            periodEnd: currentWindow.end,
            status: .pending,
            claimedAmount: 0.0
        )
        log.credit = credit
        credit.periodLogs.append(log)
        context.insert(log)
        return log
    }

    // MARK: - Evaluate & Advance Periods (handles cascading gaps)

    static func evaluateAndAdvancePeriods(for credits: [Credit], now: Date = Date(), context: ModelContext) {
        for credit in credits {
            evaluatePeriods(for: credit, now: now, context: context)
        }
    }

    static func evaluatePeriods(for credit: Credit, now: Date = Date(), context: ModelContext) {
        let sortedLogs = credit.periodLogs.sorted { $0.periodStart < $1.periodStart }

        // Find the last log and check if it's expired
        for log in sortedLogs {
            if log.periodEnd < now {
                // Period has ended – finalize if still pending
                if log.periodStatus == .pending {
                    log.periodStatus = .missed
                }
                // partiallyClaimed stays as-is (already recorded claimedAmount)
            }
        }

        // Fill any gaps between last recorded period and now
        if let lastLog = sortedLogs.last {
            if lastLog.periodEnd < now {
                // We need to fill gaps from the period AFTER the last log up to now
                var scanDate = nextPeriodStart(after: lastLog.periodEnd, timeframe: credit.timeframeType)
                let currentWindow = currentPeriod(for: credit, referenceDate: now)

                while scanDate < currentWindow.start {
                    let gapWindow = currentPeriod(for: credit, referenceDate: scanDate)
                    // Only insert if not already present
                    if !credit.periodLogs.contains(where: { $0.periodLabel == gapWindow.label }) {
                        let missedLog = PeriodLog(
                            periodLabel: gapWindow.label,
                            periodStart: gapWindow.start,
                            periodEnd: gapWindow.end,
                            status: .missed,
                            claimedAmount: 0.0
                        )
                        missedLog.credit = credit
                        credit.periodLogs.append(missedLog)
                        context.insert(missedLog)
                    }
                    scanDate = nextPeriodStart(after: gapWindow.end, timeframe: credit.timeframeType)
                }
            }
        }

        // Ensure current period exists
        ensureCurrentPeriodExists(for: credit, now: now, context: context)
    }

    // MARK: - Active Period Log

    static func activePeriodLog(for credit: Credit, now: Date = Date()) -> PeriodLog? {
        let currentWindow = currentPeriod(for: credit, referenceDate: now)
        return credit.periodLogs.first(where: { $0.periodLabel == currentWindow.label })
    }

    // MARK: - ROI Helpers

    static func totalClaimedThisYear(for credit: Credit, year: Int? = nil) -> Double {
        let targetYear = year ?? DateHelpers.calendar.component(.year, from: Date())
        return credit.periodLogs
            .filter { DateHelpers.calendar.component(.year, from: $0.periodStart) == targetYear }
            .reduce(0) { $0 + $1.claimedAmount }
    }
}
