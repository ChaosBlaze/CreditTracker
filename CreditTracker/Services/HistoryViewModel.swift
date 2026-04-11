import Foundation
import FirebaseCore
import FirebaseFirestore

// MARK: - Supporting Value Types

/// Lightweight Firestore-hydrated card record used for in-memory resolution.
struct HistoryCard {
    let id: String
    let name: String
    let annualFee: Double
    let gradientStartHex: String
    let gradientEndHex: String

    init?(doc: QueryDocumentSnapshot) {
        let d = doc.data()
        guard let name = d["name"] as? String else { return nil }
        self.id               = doc.documentID
        self.name             = name
        self.annualFee        = (d["annualFee"] as? Double) ?? (d["annualFee"] as? NSNumber)?.doubleValue ?? 0
        self.gradientStartHex = d["gradientStartHex"] as? String ?? "#A8A9AD"
        self.gradientEndHex   = d["gradientEndHex"]   as? String ?? "#E8E8E8"
    }
}

/// Lightweight Firestore-hydrated credit record used for in-memory resolution.
struct HistoryCredit {
    let id: String
    let name: String
    let totalValue: Double
    let cardID: String?

    init?(doc: QueryDocumentSnapshot) {
        let d = doc.data()
        guard let name = d["name"] as? String else { return nil }
        self.id         = doc.documentID
        self.name       = name
        self.totalValue = (d["totalValue"] as? Double) ?? (d["totalValue"] as? NSNumber)?.doubleValue ?? 0
        self.cardID     = d["cardID"] as? String
    }
}

/// Raw Firestore PeriodLog document — parsed before card/credit resolution.
private struct RawPeriodLog {
    let id: String
    let periodLabel: String
    let periodStart: Date
    let periodEnd: Date
    let status: PeriodStatus
    let claimedAmount: Double
    let creditID: String?

    init?(doc: QueryDocumentSnapshot) {
        let d = doc.data()
        guard
            let startTS = d["periodStart"] as? Timestamp,
            let endTS   = d["periodEnd"]   as? Timestamp,
            let label   = d["periodLabel"] as? String
        else { return nil }

        self.id            = doc.documentID
        self.periodLabel   = label
        self.periodStart   = startTS.dateValue()
        self.periodEnd     = endTS.dateValue()
        self.claimedAmount = (d["claimedAmount"] as? Double) ?? (d["claimedAmount"] as? NSNumber)?.doubleValue ?? 0
        self.creditID      = d["creditID"] as? String

        let raw    = d["status"] as? String ?? ""
        self.status = PeriodStatus(rawValue: raw) ?? .pending
    }
}

// MARK: - Resolved Feed Entry

/// A fully-flattened, resolved period log entry with all card/credit metadata
/// joined in memory. This is the model the activity feed rows consume directly.
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

// MARK: - Stats Model

struct MonthlyDataPoint: Identifiable {
    let id = UUID()
    let month: Date
    let label: String
    let value: Double
}

/// Self-contained stats snapshot for the ROI dashboard.
///
/// Deliberately a plain value type so that when aggregation moves to Cloud Functions,
/// the dashboard view can accept this struct directly from a decoded HTTP response
/// without any refactoring — only the production site in `buildStats()` changes.
struct HistoryStats {
    let totalFees: Double
    let totalExtracted: Double
    let monthlyBreakdown: [MonthlyDataPoint]

    var netROI: Double   { totalExtracted - totalFees }
    var isPositive: Bool { netROI >= 0 }

    static let empty = HistoryStats(totalFees: 0, totalExtracted: 0, monthlyBreakdown: [])
}

// MARK: - HistoryViewModel

@Observable
@MainActor
final class HistoryViewModel {

    // MARK: Observable State

    private(set) var feedEntries: [HistoryFeedEntry] = []
    private(set) var stats: HistoryStats = .empty
    private(set) var isLoading    = false
    private(set) var isLoadingMore = false
    private(set) var canLoadMore  = false
    private(set) var errorMessage: String? = nil

    // MARK: Pagination Cursor

    private var lastDocumentSnapshot: DocumentSnapshot? = nil
    private let pageSize = 50

    // MARK: Resolution Maps

    private var cardMap:   [String: HistoryCard]   = [:]
    private var creditMap: [String: HistoryCredit] = [:]

    // MARK: Firestore

    private var db: Firestore { Firestore.firestore() }

    private var userID: String {
        UserDefaults.standard.string(forKey: Constants.firestoreUserIDKey) ?? ""
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
    /// Call from `.task {}` in the view.
    func load() async {
        guard feedEntries.isEmpty else { return }
        await fetchFresh()
    }

    /// Forces a full reload — clears existing state first.
    /// Call from `.refreshable {}` in the view.
    func reload() async {
        feedEntries          = []
        lastDocumentSnapshot = nil
        canLoadMore          = false
        stats                = .empty
        await fetchFresh()
    }

    /// Appends the next page of results for infinite scroll.
    func loadMore() async {
        guard !isLoadingMore, canLoadMore else { return }
        isLoadingMore = true

        do {
            let result = try await fetchPeriodLogsPage(after: lastDocumentSnapshot)
            feedEntries.append(contentsOf: result.entries)
            lastDocumentSnapshot = result.cursor
            canLoadMore          = result.canLoadMore
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMore = false
    }

    // MARK: - Private — Orchestration

    private func fetchFresh() async {
        guard !isLoading else { return }
        guard FirebaseApp.app() != nil, !userID.isEmpty else {
            errorMessage = "Sync is not configured for this device."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // 1. Build card/credit resolution maps and fetch this year's logs
            //    for stats — all three run concurrently.
            async let cardTask     = fetchCards()
            async let creditTask   = fetchCredits()
            async let yearLogsTask = fetchCurrentYearLogs()

            let (cards, credits, yearLogs) = try await (cardTask, creditTask, yearLogsTask)

            cardMap   = Dictionary(uniqueKeysWithValues: cards.map   { ($0.id, $0) })
            creditMap = Dictionary(uniqueKeysWithValues: credits.map { ($0.id, $0) })

            // 2. Build stats from the full-year logs (independent of feed pagination).
            stats = buildStats(from: yearLogs)

            // 3. Fetch the activity feed's first page — resolution maps are ready.
            let result = try await fetchPeriodLogsPage(after: nil)
            feedEntries          = result.entries
            lastDocumentSnapshot = result.cursor
            canLoadMore          = result.canLoadMore

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Private — Firestore Fetches

    private func fetchCards() async throws -> [HistoryCard] {
        let snap = try await userCollection("cards").getDocuments()
        return snap.documents.compactMap { HistoryCard(doc: $0) }
    }

    private func fetchCredits() async throws -> [HistoryCredit] {
        let snap = try await userCollection("credits").getDocuments()
        return snap.documents.compactMap { HistoryCredit(doc: $0) }
    }

    /// Fetches all PeriodLogs that started in the current calendar year.
    /// Used exclusively for ROI stats — not paginated.
    private func fetchCurrentYearLogs() async throws -> [RawPeriodLog] {
        let year = Calendar.current.component(.year, from: Date())
        guard let startOfYear = Calendar.current.date(
            from: DateComponents(year: year, month: 1, day: 1)
        ) else { return [] }

        let snap = try await userCollection("periodLogs")
            .whereField("periodStart", isGreaterThanOrEqualTo: Timestamp(date: startOfYear))
            .getDocuments()

        return snap.documents.compactMap { RawPeriodLog(doc: $0) }
    }

    private struct PageResult {
        let entries: [HistoryFeedEntry]
        let cursor: DocumentSnapshot?
        let canLoadMore: Bool
    }

    /// Fetches a single page of the activity feed, ordered by `periodStart` descending.
    private func fetchPeriodLogsPage(after cursor: DocumentSnapshot?) async throws -> PageResult {
        var query: Query = userCollection("periodLogs")
            .order(by: "periodStart", descending: true)
            .limit(to: pageSize)

        if let cursor { query = query.start(afterDocument: cursor) }

        let snap    = try await query.getDocuments()
        let entries = snap.documents.compactMap { doc -> HistoryFeedEntry? in
            guard let raw = RawPeriodLog(doc: doc) else { return nil }
            return resolve(raw)
        }

        return PageResult(
            entries:     entries,
            cursor:      snap.documents.last,
            canLoadMore: snap.documents.count == pageSize
        )
    }

    // MARK: - Private — Resolution

    /// Joins a raw log with card and credit metadata using the in-memory lookup maps.
    private func resolve(_ raw: RawPeriodLog) -> HistoryFeedEntry {
        let credit = raw.creditID.flatMap  { creditMap[$0] }
        let card   = credit?.cardID.flatMap { cardMap[$0] }

        return HistoryFeedEntry(
            id:               raw.id,
            periodLabel:      raw.periodLabel,
            periodStart:      raw.periodStart,
            periodEnd:        raw.periodEnd,
            status:           raw.status,
            claimedAmount:    raw.claimedAmount,
            creditName:       credit?.name            ?? "Unknown Credit",
            creditTotalValue: credit?.totalValue      ?? 0,
            cardName:         card?.name              ?? "Unknown Card",
            gradientStartHex: card?.gradientStartHex  ?? "#A8A9AD",
            gradientEndHex:   card?.gradientEndHex    ?? "#E8E8E8"
        )
    }

    // MARK: - Private — Stats

    private func buildStats(from yearLogs: [RawPeriodLog]) -> HistoryStats {
        let calendar    = Calendar.current
        let formatter   = DateFormatter()
        formatter.dateFormat = "MMM"
        let currentYear = calendar.component(.year, from: Date())

        let totalFees      = cardMap.values.reduce(0) { $0 + $1.annualFee }
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

    // MARK: - Private — Helpers

    private func userCollection(_ name: String) -> CollectionReference {
        db.collection("users").document(userID).collection(name)
    }
}
