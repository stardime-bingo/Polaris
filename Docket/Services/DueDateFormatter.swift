import Foundation

struct DueDateFormatter {
    static let locale = Locale(identifier: "zh_Hans_CN")

    enum CountdownState: Equatable {
        case completed
        case noDeadline
        case remainingDays(Int)
        case remainingDaysHours(Int, Int)
        case remainingHours(Int)
        case remainingLessThanHour
        case dueNow
        case overdueDays(Int)
        case overdueHours(Int)
        case overdueLessThanHour
    }

    static func format(_ date: Date, hasTime: Bool = false, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        let day: String
        switch days {
        case 0: day = "今天"
        case 1: day = "明天"
        case -1: day = "昨天"
        default:
            let f = DateFormatter(); f.locale = locale; f.calendar = calendar; f.timeZone = calendar.timeZone
            f.dateFormat = calendar.isDate(date, equalTo: now, toGranularity: .year) ? "M月d日" : "yyyy年M月d日"
            day = f.string(from: date)
        }
        guard hasTime else { return day }
        let f = DateFormatter(); f.locale = locale; f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = "HH:mm"
        return day + " " + f.string(from: date)
    }
    /// A date-only goal remains available through its entire local calendar day.
    /// This is a display calculation; the stored date and reminder time stay intact.
    static func effectiveDeadline(_ date: Date, hasTime: Bool, calendar: Calendar = .current) -> Date {
        hasTime ? date : calendar.dateInterval(of: .day, for: date)?.end ?? date
    }

    /// Durations use elapsed hours (a day is 24 hours), while date-only boundaries
    /// use the calendar so 23-hour and 25-hour daylight-saving days stay correct.
    /// Displayed whole units round down; sub-hour values have explicit wording.
    static func countdownState(_ date: Date?, hasTime: Bool = false, isCompleted: Bool = false,
                               now: Date = Date(), calendar: Calendar = .current) -> CountdownState {
        if isCompleted { return .completed }
        guard let date else { return .noDeadline }
        let seconds = effectiveDeadline(date, hasTime: hasTime, calendar: calendar).timeIntervalSince(now)
        if seconds == 0 { return .dueNow }
        if seconds < 0 {
            let elapsed = -seconds
            if elapsed >= 86_400 { return .overdueDays(Int(elapsed / 86_400)) }
            if elapsed >= 3_600 { return .overdueHours(Int(elapsed / 3_600)) }
            return .overdueLessThanHour
        }
        if seconds >= 7 * 86_400 { return .remainingDays(Int(seconds / 86_400)) }
        if seconds > 48 * 3_600 {
            let hours = Int(seconds / 3_600)
            return .remainingDaysHours(hours / 24, hours % 24)
        }
        if seconds >= 3_600 { return .remainingHours(Int(seconds / 3_600)) }
        return .remainingLessThanHour
    }

    static func countdown(_ date: Date?, hasTime: Bool = false, isCompleted: Bool = false,
                          now: Date = Date(), calendar: Calendar = .current) -> String {
        L10n.countdown(countdownState(date, hasTime: hasTime, isCompleted: isCompleted, now: now, calendar: calendar))
    }

    static func remaining(_ date: Date, hasTime: Bool = false, now: Date = Date(), calendar: Calendar = .current) -> String {
        countdown(date, hasTime: hasTime, now: now, calendar: calendar)
    }

    /// Always includes the year, unlike the relative date used in other views.
    static func absolute(_ date: Date, hasTime: Bool = false, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = hasTime ? "yyyy年M月d日 HH:mm" : "yyyy年M月d日"
        let value = formatter.string(from: date)
        return hasTime ? value : L10n.dateOnlyDeadline(value)
    }
}
