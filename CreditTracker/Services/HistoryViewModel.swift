import Foundation
import SwiftData

// MARK: - Stats Value Types
//
// These value types are kept as-is so HistoryView and HistoryROIDashboard require
// zero changes. Only the production site (HistoryViewModel) changes — the view
// still consumes the same HistoryFeedEntry and HistoryStats structs.

struct MonthlyDataPoint: Identifiable {
    let id = UUID()
    let month: Date
    let label: String
    let value: Double
}

/// Self-contained stats snapshot for the ROI dashboard.
///
/// Designed to be forward-compatible: when aggregation moves to a Cloud Function
/// (stats/ytd document in Firestore), only `HistoryViewModel.buildStats()` changes
/// — this struct and all views consuming it remain untouched.
struct HistoryStats {
    let totalFees: Double
    let totalExtracted: Double
    let monthlyBreakdown: [MonthlyDataPoint]

    var netROI:     Double { totalExtracted - totalFees }
    var isPositive: Bool   { netROI >= 0 }

    static let empty = HistoryStats(totalFees: 0, totalExtracted: 0, monthlyBreakdown: [])
}

// MARK: - Resolved Feed Entry

/// A fully-flattened period log entry with all card/credit metadata joined.
/// Consumed by ActivityFeedRow — unchanged from the Firestore-era implementation.
struct HistoryFeedEntry: Identifiable {
    let id: String
    let periodLabel: String
    let periodStart: Date
    let periodEnd: Date
    let status: PeriodStatus
    let claimedAmount: Double
    let creditName: String
    let creditTotalValue: Double
    let cardName: String
    let gradientStartHex: String
    let gradientEndHex: String
}

// MARK: - HistoryViewModel

/// SwiftData-first history view model (Phase 3 refactor).
///
/// ## What changed
/// - Reads period logs from SwiftData via `FetchDescriptor` (zero Firestore reads).
/// - Works fully offline — no network required.
/// - Stats are computed locally from SwiftData (identical algorithm to the old
///   `buildStats(from:)` — same output, same struct types).
/// - Eliminates `HistoryCard`, `HistoryCredit`, `RawPeriodLog` mirror structs
///   and the three parallel Firestore fetches they required.
/// - Pagination uses `FetchDescriptor.fetchOffset` instead of a Firestore cursor.
///
/// ## Forward Compatibility
/// When the `aggregateYTDStats` Cloud Function is deployed, `buildStats()` can be
/// replaced with a single `Firestore.document("users/\(id)/stats/ytd").getDocument()`
/// call — `HistoryView` and `HistoryROIDashboard` require zero changes.
@Observable
@MainActor
final class HistoryViewModel {

    // MARK: Observable State

    private(set) var feedEntries:    [HistoryFeedEntry] = []
    private(set) var stats:          HistoryStats       = .empty
    private(set) var isLoading:      Bool               = false
    private(set) var isLoadingMore:  Bool               = false
    private(set) var canLoadMore:    Bool               = false
    private(set) var errorMessage:   String?            = nil

    // MARK: Pagination

    private var pageOffset = 0
    private let pageSize   = 50

    // MARK: SwiftData Access

    /// Reads the app's shared model container (set during app startup in CreditTrackerApp).
    /// Using mainContext is safe here because HistoryViewModel is @MainActor.
    private var context: ModelContext? {
        CreditTrackerApp.sharedModelContainer?.mainContext
    }

    // MARK: Computed Helpers

    var missedEntries: [HistoryFeedEntry] {
        feedEntries.filter { $0.status == .missed }
    }

    var hasMissedEntries: Bool { !missedEntries.isEmpty }

    /// Total un-captured value across all missed entries in the current feed.
    var totalMissedValue: Double {
        missedEntries.reduce(0) { $0 + max(0, $1.creditTotalValue - $1.claimedAmount) }
    }

    // MARK: - Public API

    /// Loads the first page. Idempotent: skips if data is already loaded.
    func load() async {
        guard feedEntries.isEmpty else { return }
        fetchFresh()
    }

    /// Forces a full reload — clears existing state first.
    func reload() async {
        feedEntries   = []
        pageOffset    = 0
        canLoadMore   = false
        stats         = .empty
        errorMessage  = nil
        fetchFresh()
    }

    /// Appends the next page of results for infinite scroll.
    func loadMore() async {
        guard !isLoadingMore, canLoadMore else { return }
        isLoadingMore = true
        appendNextPage()
        isLoadingMore = false
    }

    // MARK: - Private — Data Loading

    private func fetchFresh() {
        guard !isLoading else { return }
        guard let context else {
            errorMessage = "Data store is not available."
            return
        }

        isLoading    = true
        errorMessage = nil

        // Compute stats from current-year logs (same algorithm as before, now from SwiftData).
        let yearLogs = fetchCurrentYearLogs(in: context)
        stats = buildStats(from: yearLogs, context: context)

        // Load first page.
        pageOffset = 0
        let (entries, hasMore) = fetchPage(offset: 0, in: context)
        feedEntries = entries
        pageOffset  = entries.count
        canLoadMore = hasMore

        isLoading = false
    }

    private func appendNextPage() {
        guard let context else { return }
        let (entries, hasMore) = fetchPage(offset: pageOffset, in: context)
        feedEntries.append(contentsOf: entries)
        pageOffset  += entries.count
        canLoadMore  = hasMore
    }

    // MARK: - Private — SwiftData Queries

    /// Fetches one page of PeriodLogs sorted by periodStart descending.
    private func fetchPage(offset: Int, in context: ModelContext) -> ([HistoryFeedEntry], Bool) {
        var descriptor = FetchDescriptor<PeriodLog>(
            sortBy: [SortDescriptor(\.periodStart, order: .reverse)]
        )
        descriptor.fetchLimit  = pageSize
        descriptor.fetchOffset = offset

        let logs    = (try? context.fetch(descriptor)) ?? []
        let entries = logs.map { resolve($0) }
        return (entries, logs.count == pageSize)
    }

    /// Fetches all PeriodLogs for the current calendar year (used for stats only).
    private func fetchCurrentYearLogs(in context: ModelContext) -> [PeriodLog] {
        let year = Calendar.current.component(.year, from: Date())
        guard let startOfYear = Calendar.current.date(
            from: DateComponents(year: year, month: 1, day: 1)
        ) else { return [] }

        let descriptor = FetchDescriptor<PeriodLog>(
            predicate: #Predicate { $0.periodStart >= startOfYear }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Private — Resolution

    /// Joins a PeriodLog with its Credit and Card metadata via SwiftData relationships.
    /// Falls back to placeholder strings for orphaned logs (e.g. during initial sync).
    private func resolve(_ log: PeriodLog) -> HistoryFeedEntry {
        let credit = log.credit
        let card   = credit?.card

        return HistoryFeedEntry(
            id:               log.id.uuidString,
            periodLabel:      log.periodLabel,
            periodStart:      log.periodStart,
            periodEnd:        log.periodEnd,
            status:           log.periodStatus,
            claimedAmount:    log.claimedAmount,
            creditName:       credit?.name              ?? "Unknown Credit",
            creditTotalValue: credit?.totalValue        ?? 0,
            cardName:         card?.name                ?? "Unknown Card",
            gradientStartHex: card?.gradientStartHex    ?? "#A8A9AD",
            gradientEndHex:   card?.gradientEndHex      ?? "#E8E8E8"
        )
    }

    // MARK: - Private — Stats

    private func buildStats(from yearLogs: [PeriodLog], context: ModelContext) -> HistoryStats {
        let calendar    = Calendar.current
        let formatter   = DateFormatter()
        formatter.dateFormat = "MMM"
        let currentYear = calendar.component(.year, from: Date())

        // Sum annual fees across all cards (same source of truth as DashboardView).
        let cards      = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        let totalFees  = cards.reduce(0) { $0 + $1.annualFee }

        let totalExtracted = yearLogs.reduce(0) { $0 + $1.claimedAmount }

        // Group claimed amounts by calendar month.
        var monthMap: [Int: Double] = [:]
        for log in yearLogs where log.claimedAmount > 0 {
            let m = calendar.component(.month, from: log.periodStart)
            monthMap[m, default: 0] += log.claimedAmount
        }

        let breakdown: [MonthlyDataPoint] = (1...12).compactMap { month in
            guard let value = monthMap[month], value > 0 else { return nil }
            guard let date  = calendar.date(
                from: DateComponents(year: currentYear, month: month)
            ) else { return nil }
            return MonthlyDataPoint(month: date, label: formatter.string(from: date), value: value)
        }

        return HistoryStats(
            totalFees:        totalFees,
            totalExtracted:   totalExtracted,
            monthlyBreakdown: breakdown
        )
    }
}
