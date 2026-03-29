import Foundation

struct DateHelpers {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }()

    static func monthLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    static func quarterLabel(for date: Date) -> String {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        let quarter = (month - 1) / 3 + 1
        return "Q\(quarter) \(year)"
    }

    static func halfYearLabel(for date: Date) -> String {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        let half = month <= 6 ? "H1" : "H2"
        return "\(half) \(year)"
    }

    static func yearLabel(for date: Date) -> String {
        let year = calendar.component(.year, from: date)
        return "\(year)"
    }

    static func startOfMonth(for date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)!.start
    }

    static func endOfMonth(for date: Date) -> Date {
        let start = startOfMonth(for: date)
        return calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start)!
    }

    static func startOfQuarter(for date: Date) -> Date {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        let quarterStartMonth = ((month - 1) / 3) * 3 + 1
        return calendar.date(from: DateComponents(year: year, month: quarterStartMonth, day: 1))!
    }

    static func endOfQuarter(for date: Date) -> Date {
        let start = startOfQuarter(for: date)
        return calendar.date(byAdding: DateComponents(month: 3, second: -1), to: start)!
    }

    static func startOfHalfYear(for date: Date) -> Date {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        let halfStartMonth = month <= 6 ? 1 : 7
        return calendar.date(from: DateComponents(year: year, month: halfStartMonth, day: 1))!
    }

    static func endOfHalfYear(for date: Date) -> Date {
        let start = startOfHalfYear(for: date)
        return calendar.date(byAdding: DateComponents(month: 6, second: -1), to: start)!
    }

    static func startOfYear(for date: Date) -> Date {
        let year = calendar.component(.year, from: date)
        return calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
    }

    static func endOfYear(for date: Date) -> Date {
        let start = startOfYear(for: date)
        return calendar.date(byAdding: DateComponents(year: 1, second: -1), to: start)!
    }

    static func daysUntil(_ date: Date, from now: Date = Date()) -> Int {
        let components = calendar.dateComponents([.day], from: now, to: date)
        return components.day ?? 0
    }

    static func shortDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
