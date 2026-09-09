import Foundation

/// Deliberately bounded Chinese date grammar; never accepts normalized invalid dates.
enum GoalDateParser {
    static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        let today = calendar.startOfDay(for: now)
        let offsets = ["今天": 0, "明天": 1, "后天": 2, "下周": 7]
        if let offset = offsets[value] { return calendar.date(byAdding: .day, value: offset, to: today) }
        if ["周末", "本周末", "本周日", "本周天"].contains(value) { return GoalPeriod.end(of: .weekOfYear, from: now, calendar: calendar) }
        if ["下周末", "下周日", "下周天"].contains(value), let next = calendar.date(byAdding: .day, value: 7, to: today) { return GoalPeriod.end(of: .weekOfYear, from: next, calendar: calendar) }
        if ["月底", "月末", "本月底", "本月末"].contains(value) { return GoalPeriod.end(of: .month, from: now, calendar: calendar) }
        if ["下月底", "下月末"].contains(value), let next = calendar.date(byAdding: .month, value: 1, to: today) { return GoalPeriod.end(of: .month, from: next, calendar: calendar) }
        if ["年底", "年末", "今年底"].contains(value) { return GoalPeriod.end(of: .year, from: now, calendar: calendar) }
        if let parts = captures("^([0-9]{1,3})天后$", value), let count = Int(parts[0]) { return calendar.date(byAdding: .day, value: count, to: today) }
        var year = calendar.component(.year, from: now)
        var month: Int?
        var day: Int?
        if let parts = captures("^([0-9]{4})[-/年]([0-9]{1,2})[-/月]([0-9]{1,2})日?$", value) {
            year = Int(parts[0])!; month = Int(parts[1]); day = Int(parts[2])
        } else if let parts = captures("^([0-9]{1,2})月([0-9]{1,2})日?$", value) { month = Int(parts[0]); day = Int(parts[1]) }
        guard year >= 1900, year <= 9999, let month, let day,
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }
    private static func captures(_ pattern: String, _ value: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: value).map { String(value[$0]) } }
    }
}
extension GoalScheduleRules {
    static func changingDate(_ item: TodoItem, to date: Date?, calendar: Calendar = .current) -> TodoItem {
        var updated = item
        updated.dueDate = date.map { calendar.startOfDay(for: $0) }
        if let date, item.hasDueTime, let old = item.dueDate {
            let time = calendar.dateComponents([.hour, .minute], from: old)
            updated.dueDate = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: date)
        }
        if date == nil { updated.hasDueTime = false; updated.recurrence = nil }
        return updated
    }
}
