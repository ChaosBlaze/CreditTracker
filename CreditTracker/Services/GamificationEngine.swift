import Foundation
import SwiftData

/// Manages achievement evaluation, streak tracking, and stats updates.
struct GamificationEngine {

    // MARK: - Achievement Definitions

    static let achievementDefinitions: [(key: String, name: String, icon: String, requirement: String)] = [
        ("first_claim", "First Claim", "checkmark.seal.fill", "Claim any credit for the first time"),
        ("hot_streak_7", "Hot Streak", "flame.fill", "7 consecutive periods without a miss"),
        ("hot_streak_30", "Inferno", "flame.circle.fill", "30 consecutive periods without a miss"),
        ("diamond_hands", "Diamond Hands", "diamond.fill", "Claim every credit for 3 months straight"),
        ("roi_positive", "In the Green", "chart.line.uptrend.xyaxis", "Total claimed exceeds total annual fees"),
        ("perfect_month", "Perfect Month", "star.fill", "Every credit claimed in full in one month"),
        ("speed_demon", "Speed Demon", "bolt.fill", "Claim a credit within 24h of period start"),
        ("big_saver", "Big Saver", "banknote.fill", "Lifetime savings exceed $1,000"),
        ("collector", "Collector", "rectangle.stack.fill", "Track 5+ cards simultaneously"),
    ]

    // MARK: - Seed Achievements

    static func seedAchievements(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Achievement>())) ?? []
        let existingKeys = Set(existing.map { $0.key })

        for def in achievementDefinitions {
            if !existingKeys.contains(def.key) {
                let achievement = Achievement(
                    key: def.key,
                    name: def.name,
                    icon: def.icon,
                    requirement: def.requirement
                )
                context.insert(achievement)
            }
        }

        // Ensure UserStats exists
        let stats = (try? context.fetch(FetchDescriptor<UserStats>())) ?? []
        if stats.isEmpty {
            context.insert(UserStats())
        }

        try? context.save()
    }

    // MARK: - Record a Claim

    static func recordClaim(
        amount: Double,
        credit: Credit,
        cards: [Card],
        context: ModelContext
    ) -> [Achievement] {
        guard let stats = try? context.fetch(FetchDescriptor<UserStats>()).first else { return [] }
        let achievements = (try? context.fetch(FetchDescriptor<Achievement>())) ?? []
        var unlocked: [Achievement] = []

        // Update stats
        stats.lifetimeSaved += amount
        stats.totalClaimCount += 1
        stats.lastClaimDate = Date()

        // Check achievements
        // 1. First Claim
        if let a = achievements.first(where: { $0.key == "first_claim" && !$0.isUnlocked }) {
            a.unlockedAt = Date()
            unlocked.append(a)
        }

        // 2. Speed Demon - claimed within 24h of period start
        if let period = PeriodEngine.activePeriodLog(for: credit) {
            let hoursSinceStart = Date().timeIntervalSince(period.periodStart) / 3600
            if hoursSinceStart <= 24 {
                if let a = achievements.first(where: { $0.key == "speed_demon" && !$0.isUnlocked }) {
                    a.unlockedAt = Date()
                    unlocked.append(a)
                }
            }
        }

        // 3. Big Saver - lifetime > $1000
        if stats.lifetimeSaved >= 1000 {
            if let a = achievements.first(where: { $0.key == "big_saver" && !$0.isUnlocked }) {
                a.unlockedAt = Date()
                unlocked.append(a)
            }
        }

        // 4. Collector - 5+ cards
        if cards.count >= 5 {
            if let a = achievements.first(where: { $0.key == "collector" && !$0.isUnlocked }) {
                a.unlockedAt = Date()
                unlocked.append(a)
            }
        }

        // 5. ROI Positive
        let totalFees = cards.reduce(0.0) { $0 + $1.annualFee }
        let totalClaimed = cards.flatMap { $0.credits }.reduce(0.0) {
            $0 + PeriodEngine.totalClaimedThisYear(for: $1)
        }
        if totalClaimed > totalFees {
            if let a = achievements.first(where: { $0.key == "roi_positive" && !$0.isUnlocked }) {
                a.unlockedAt = Date()
                unlocked.append(a)
            }
        }

        // 6. Perfect Month - all credits fully claimed this month
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: Date())
        let currentYear = calendar.component(.year, from: Date())
        let allCredits = cards.flatMap { $0.credits }
        let monthlyCredits = allCredits.filter { $0.timeframeType == .monthly }
        if !monthlyCredits.isEmpty {
            let allClaimed = monthlyCredits.allSatisfy { credit in
                guard let period = PeriodEngine.activePeriodLog(for: credit) else { return false }
                let logMonth = calendar.component(.month, from: period.periodStart)
                let logYear = calendar.component(.year, from: period.periodStart)
                return logMonth == currentMonth && logYear == currentYear && period.periodStatus == .claimed
            }
            if allClaimed {
                if let a = achievements.first(where: { $0.key == "perfect_month" && !$0.isUnlocked }) {
                    a.unlockedAt = Date()
                    unlocked.append(a)
                }
            }
        }

        try? context.save()
        return unlocked
    }

    // MARK: - Update Streak (called during period evaluation)

    static func updateStreak(cards: [Card], context: ModelContext) {
        guard let stats = try? context.fetch(FetchDescriptor<UserStats>()).first else { return }
        let achievements = (try? context.fetch(FetchDescriptor<Achievement>())) ?? []

        let allCredits = cards.flatMap { $0.credits }
        let allLogs = allCredits.flatMap { $0.periodLogs }.sorted { $0.periodEnd > $1.periodEnd }

        // Count consecutive non-missed periods from most recent
        var streak = 0
        for log in allLogs {
            if log.periodEnd > Date() { continue } // Skip future/current periods
            if log.periodStatus == .missed {
                break
            }
            streak += 1
        }

        stats.currentStreak = streak
        if streak > stats.longestStreak {
            stats.longestStreak = streak
        }

        // Check streak achievements
        if streak >= 7 {
            if let a = achievements.first(where: { $0.key == "hot_streak_7" && !$0.isUnlocked }) {
                a.unlockedAt = Date()
            }
        }
        if streak >= 30 {
            if let a = achievements.first(where: { $0.key == "hot_streak_30" && !$0.isUnlocked }) {
                a.unlockedAt = Date()
            }
        }

        // Diamond Hands - all credits claimed for 3 months straight
        let calendar = Calendar.current
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        let recentLogs = allCredits.flatMap { $0.periodLogs }.filter {
            $0.periodEnd < Date() && $0.periodStart >= threeMonthsAgo
        }
        if !recentLogs.isEmpty && recentLogs.allSatisfy({ $0.periodStatus == .claimed }) {
            if let a = achievements.first(where: { $0.key == "diamond_hands" && !$0.isUnlocked }) {
                a.unlockedAt = Date()
            }
        }

        try? context.save()
    }
}
