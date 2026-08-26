// DateParser.swift
// Docket — macOS Menu Bar Task Manager
// Created by @santoru

import Foundation

/// Parses natural language strings into dates.
/// Supports: "today", "tomorrow", "next monday", "in 2 hours", "friday 3pm", etc.
struct DateParser {
    static func parse(_ input: String) -> Date? {
        let text = input.lowercased().trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return nil }

        let calendar = Calendar.current
        let now = Date()

        // Time-of-day keywords
        switch text {
        case "now": return now
        case "noon": return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)
        case "midnight": return calendar.date(byAdding: .day, value: 1, to: calendar.date(bySettingHour: 0, minute: 0, second: 0, of: now)!)
        case "tonight": return calendar.date(bySettingHour: 21, minute: 0, second: 0, of: now)
        case "this evening": return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now)
        case "this afternoon": return calendar.date(bySettingHour: 14, minute: 0, second: 0, of: now)
        case "this morning": return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)
        case "end of day", "eod": return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now)
        case "end of week", "eow":
            let friday = nextWeekday(6, after: now)
            return friday.flatMap { calendar.date(bySettingHour: 17, minute: 0, second: 0, of: $0) }
        case "today": return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now)
        default: break
        }

        // "tomorrow" with optional time
        if text.hasPrefix("tomorrow") {
            let base = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            return applyTime(text.replacingOccurrences(of: "tomorrow", with: ""), to: base) ?? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base)
        }

        // "day after tomorrow"
        if text == "day after tomorrow" {
            let base = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now))!
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base)
        }

        // "later" = 3 hours from now
        if text == "later" {
            return calendar.date(byAdding: .hour, value: 3, to: now)
        }

        // "this weekend" = Saturday 10am
        if text == "this weekend" || text == "weekend" {
            return nextWeekday(7, after: now).flatMap { calendar.date(bySettingHour: 10, minute: 0, second: 0, of: $0) }
        }

        // "next week" = next Monday 9am
        if text == "next week" {
            return nextWeekday(2, after: now).flatMap { calendar.date(bySettingHour: 9, minute: 0, second: 0, of: $0) }
        }

        // "in X minutes/hours/days"
        if text.hasPrefix("in ") {
            let parts = text.dropFirst(3).split(separator: " ")
            if parts.count >= 2, let value = Int(parts[0]) {
                let unit = String(parts[1])
                if unit.hasPrefix("min") { return calendar.date(byAdding: .minute, value: value, to: now) }
                if unit.hasPrefix("hour") { return calendar.date(byAdding: .hour, value: value, to: now) }
                if unit.hasPrefix("day") { return calendar.date(byAdding: .day, value: value, to: now) }
                if unit.hasPrefix("week") { return calendar.date(byAdding: .day, value: value * 7, to: now) }
            }
        }

        // "next monday", "next friday", etc.
        if text.hasPrefix("next ") {
            let dayName = String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if let weekday = weekdayNumber(dayName) {
                return nextWeekday(weekday, after: now)
            }
        }

        // Bare weekday: "monday" (default 9am), or weekday + suffix such as
        // "friday 3pm" or "friday noon". A weekday with an EMPTY suffix
        // returns the weekday's default 9am; a weekday with a NON-EMPTY but
        // malformed suffix (e.g. "friday abc", "friday 25pm", "friday 9:99")
        // returns nil rather than silently falling back to 9am — otherwise
        // typos would land tasks on the wrong time without the user
        // realising the suffix was ignored.
        let firstWord = String(text.split(separator: " ").first ?? "")
        if let weekday = weekdayNumber(firstWord) {
            let base = nextWeekday(weekday, after: now) ?? now
            let timeStr = text
                .replacingOccurrences(of: firstWord, with: "")
                .trimmingCharacters(in: .whitespaces)
            if timeStr.isEmpty { return base }          // bare weekday → default 9am
            return applyTime(timeStr, to: base)          // malformed suffix → nil
        }

        // Try Apple's DataDetector as fallback (use the normalized text so
        // behavior is consistent with the rest of the parser).
        return detectDate(from: text)
    }

    // MARK: - Helpers

    private static func weekdayNumber(_ name: String) -> Int? {
        let map = ["sunday": 1, "sun": 1, "monday": 2, "mon": 2, "tuesday": 3, "tue": 3,
                   "wednesday": 4, "wed": 4, "thursday": 5, "thu": 5, "friday": 6, "fri": 6,
                   "saturday": 7, "sat": 7]
        return map[name.lowercased()]
    }

    private static func nextWeekday(_ weekday: Int, after date: Date) -> Date? {
        let calendar = Calendar.current
        let current = calendar.component(.weekday, from: date)
        var daysAhead = weekday - current
        if daysAhead <= 0 { daysAhead += 7 }
        let base = calendar.date(byAdding: .day, value: daysAhead, to: date)!
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base)
    }

    private static func applyTime(_ timeStr: String, to date: Date) -> Date? {
        let text = timeStr.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "at ", with: "")
        if text.isEmpty { return nil }

        let calendar = Calendar.current

        // Time-of-day keyword shortcuts (e.g. "friday noon", "monday morning").
        // Matched after normalising whitespace but before numeric parsing so
        // e.g. "friday eod" doesn't fall through to the "reject malformed"
        // path below.
        let keyword = text.replacingOccurrences(of: " ", with: "")
        switch keyword {
        case "noon":                              return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)
        case "midnight":                          return calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date)
        case "morning", "thismorning":            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)
        case "afternoon", "thisafternoon":        return calendar.date(bySettingHour: 14, minute: 0, second: 0, of: date)
        case "evening", "thisevening":            return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: date)
        case "tonight":                           return calendar.date(bySettingHour: 21, minute: 0, second: 0, of: date)
        case "eod", "endofday":                   return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: date)
        default: break
        }

        // Match patterns like "3pm", "3:30pm", "15:00", "3 pm"
        let cleaned = keyword

        // The suffix drives the AM/PM adjustment; strip it before parsing digits.
        let hasPM = cleaned.hasSuffix("pm")
        let hasAM = cleaned.hasSuffix("am")
        var digits = cleaned
        if hasPM { digits.removeLast(2) }
        else if hasAM { digits.removeLast(2) }

        // Digits + optional ":". Any other character means malformed input —
        // treat it as unparseable instead of silently returning midnight.
        let allowed: Set<Character> = Set("0123456789:")
        guard !digits.isEmpty, digits.allSatisfy({ allowed.contains($0) }) else { return nil }

        var hour = 0
        var minute = 0

        if digits.contains(":") {
            let parts = digits.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let h = Int(parts[0]),
                  let m = Int(parts[1]) else { return nil }
            hour = h; minute = m
        } else {
            guard let h = Int(digits) else { return nil }
            hour = h
        }

        // Range validation — anything outside a valid clock time is malformed.
        // Allow 0..23 for 24-hour and 1..12 combined with am/pm.
        if hasAM || hasPM {
            guard (1...12).contains(hour) else { return nil }
        } else {
            guard (0...23).contains(hour) else { return nil }
        }
        guard (0...59).contains(minute) else { return nil }

        if hasPM && hour < 12 { hour += 12 }
        if hasAM && hour == 12 { hour = 0 }

        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
    }

    private static func detectDate(from text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let match = detector.firstMatch(in: text, range: range)
        return match?.date
    }
}
