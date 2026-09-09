import Foundation

struct DueDateFormatter {
    static let locale = Locale(identifier: "zh_Hans_CN")
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
    static func remaining(_ date: Date, hasTime: Bool = false, now: Date = Date(), calendar: Calendar = .current) -> String {
        if hasTime && abs(date.timeIntervalSince(now)) < 86400 {
            let seconds = date.timeIntervalSince(now)
            if abs(seconds) < 60 { return seconds >= 0 ? "即将截止" : "刚刚超时" }
            let minutes = Int(abs(seconds) / 60)
            let duration = minutes >= 60 ? "\(minutes / 60) 小时" : "\(minutes) 分钟"
            return (seconds >= 0 ? "还剩 " : "已过 ") + duration
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if days > 0 { return "还剩 \(days) 天" }
        if days == 0 { return "今天截止" }
        return "已过 \(-days) 天"
    }
}
