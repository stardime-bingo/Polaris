import Foundation

enum GoalPeriod: String, Codable, CaseIterable, Identifiable {
    case week, month, year, longTerm
    var id: String { rawValue }
    var title: String {
        switch self { case .week: "周"; case .month: "月度"; case .year: "年度"; case .longTerm: "长期" }
    }
    var shortTitle: String { switch self { case .week: "周"; case .month: "月"; case .year: "年"; case .longTerm: "长期" } }
    var englishTitle: String { switch self { case .week: "WEEKLY"; case .month: "MONTHLY"; case .year: "YEARLY"; case .longTerm: "LONG TERM" } }
    /// All goal weeks use Monday–Sunday in the supplied time zone, including year boundaries.
    static func weekInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        weekCalendar.minimumDaysInFirstWeek = 4
        return weekCalendar.dateInterval(of: .weekOfYear, for: date)!
    }
    // Anchor legacy inference to creation, so it doesn't drift with today's date.
    static func infer(due: Date?, created: Date, calendar: Calendar = .current) -> GoalPeriod {
        guard let due else { return .longTerm }
        if calendar.component(.month, from: due) == 12,
           calendar.component(.day, from: due) == 31,
           !calendar.isDate(due, equalTo: created, toGranularity: .month) { return .year }
        return .month
    }
    static func end(of component: Calendar.Component, from date: Date = Date(), calendar: Calendar = .current) -> Date {
        let end = component == .weekOfYear ? weekInterval(containing: date, calendar: calendar).end : calendar.dateInterval(of: component, for: date)!.end
        return calendar.date(byAdding: .day, value: -1, to: end)!
    }
}

enum GoalFilter: String, CaseIterable, Identifiable {
    case all, week, month, year, longTerm
    var id: String { rawValue }
    var title: String {
        switch self { case .all: "全部"; case .week: "本周"; case .month: "本月"; case .year: "今年"; case .longTerm: "长期" }
    }
    func includes(_ item: TodoItem, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .all: return true
        case .week:
            let interval = GoalPeriod.weekInterval(containing: now, calendar: calendar)
            let anchor = item.dueDate ?? item.createdAt
            return item.goalPeriod == .week && anchor >= interval.start && anchor < interval.end
        case .month: return item.goalPeriod == .month && calendar.isDate(item.dueDate ?? item.createdAt, equalTo: now, toGranularity: .month)
        case .year: return item.goalPeriod == .year && calendar.isDate(item.dueDate ?? item.createdAt, equalTo: now, toGranularity: .year)
        case .longTerm: return item.goalPeriod == .longTerm
        }
    }
}

enum GoalScheduleRules {
    static func changingPeriod(_ item: TodoItem, to period: GoalPeriod, now: Date = Date(), calendar: Calendar = .current) -> TodoItem {
        var updated = item
        updated.goalPeriod = period
        switch period {
        case .week: updated.dueDate = GoalPeriod.end(of: .weekOfYear, from: now, calendar: calendar)
        case .month: updated.dueDate = GoalPeriod.end(of: .month, from: now, calendar: calendar)
        case .year: updated.dueDate = GoalPeriod.end(of: .year, from: now, calendar: calendar)
        case .longTerm: updated.dueDate = nil
        }
        // A new calendar deadline is date-only, never a silently inherited midnight alarm.
        updated.hasDueTime = false
        return updated
    }
}
