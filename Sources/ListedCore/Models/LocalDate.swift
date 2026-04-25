import Foundation

/// A calendar date (year/month/day) without a time component or time zone.
///
/// `todo.txt` dates are calendar dates and must not be shifted by time zones.
public struct LocalDate: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    // MARK: - Today

    /// Today in the user's current calendar/time zone.
    public static func today(calendar: Calendar = .current, in timeZone: TimeZone = .current) -> LocalDate {
        var cal = calendar
        cal.timeZone = timeZone
        let comps = cal.dateComponents([.year, .month, .day], from: Date())
        return LocalDate(year: comps.year ?? 1970, month: comps.month ?? 1, day: comps.day ?? 1)
    }

    public static func from(_ date: Date, calendar: Calendar = .current, in timeZone: TimeZone = .current) -> LocalDate {
        var cal = calendar
        cal.timeZone = timeZone
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return LocalDate(year: comps.year ?? 1970, month: comps.month ?? 1, day: comps.day ?? 1)
    }

    // MARK: - Encoding

    /// `YYYY-MM-DD` representation. Always zero-padded.
    public var iso8601: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { iso8601 }

    /// Parse a `YYYY-MM-DD` string. Returns `nil` for invalid input.
    public static func parse(_ string: String) -> LocalDate? {
        // Fast path: must be exactly 10 chars, "YYYY-MM-DD".
        guard string.count == 10 else { return nil }
        let chars = Array(string)
        guard chars[4] == "-", chars[7] == "-" else { return nil }
        guard
            let y = Int(String(chars[0..<4])),
            let m = Int(String(chars[5..<7])),
            let d = Int(String(chars[8..<10]))
        else { return nil }
        guard (1...12).contains(m), (1...31).contains(d), y >= 1 else { return nil }
        // Lenient on day-in-month; serializer never produces invalid days.
        return LocalDate(year: y, month: m, day: d)
    }

    // MARK: - Comparable

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    // MARK: - Arithmetic

    /// Returns this date converted to `Date` (start of day, in the given time zone).
    public func date(in timeZone: TimeZone = .current, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.timeZone = timeZone
        let comps = DateComponents(year: year, month: month, day: day)
        return cal.date(from: comps) ?? Date()
    }

    public func adding(days: Int, calendar: Calendar = .current, in timeZone: TimeZone = .current) -> LocalDate {
        var cal = calendar
        cal.timeZone = timeZone
        let date = cal.date(byAdding: .day, value: days, to: self.date(in: timeZone, calendar: calendar)) ?? Date()
        return LocalDate.from(date, calendar: calendar, in: timeZone)
    }

    public func daysBetween(_ other: LocalDate, calendar: Calendar = .current, in timeZone: TimeZone = .current) -> Int {
        var cal = calendar
        cal.timeZone = timeZone
        let comps = cal.dateComponents([.day], from: self.date(in: timeZone, calendar: calendar), to: other.date(in: timeZone, calendar: calendar))
        return comps.day ?? 0
    }
}
