// main.swift — Docket logic test runner
// A dependency-free (no XCTest) harness for the app's pure logic.
// Built and run via ../run-tests.sh.

import Foundation
import AppKit
import SwiftUI
import Carbon.HIToolbox

// MARK: - Tiny harness

var passed = 0
var failed = 0

func expect(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        FileHandle.standardError.write("❌ [line \(line)] \(message)\n".data(using: .utf8)!)
    }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, line: Int = #line) {
    expect(a == b, "\(message) — expected \(b), got \(a)", line: line)
}

let cal = Calendar.current

// MARK: - DateParser

func testDateParser() {
    expect(DateParser.parse("") == nil, "empty string parses to nil")
    expect(DateParser.parse("   ") == nil, "whitespace parses to nil")

    if let noon = DateParser.parse("noon") {
        expectEqual(cal.component(.hour, from: noon), 12, "noon hour is 12")
        expect(cal.isDateInToday(noon), "noon is today")
    } else { expect(false, "noon should parse") }

    if let t = DateParser.parse("tomorrow 3pm") {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        expect(cal.isDate(t, inSameDayAs: tomorrow), "tomorrow 3pm is tomorrow")
        expectEqual(cal.component(.hour, from: t), 15, "3pm is hour 15")
    } else { expect(false, "tomorrow 3pm should parse") }

    let before = Date()
    if let t = DateParser.parse("in 2 hours") {
        let diff = t.timeIntervalSince(before)
        expect(abs(diff - 7200) < 120, "in 2 hours ≈ +7200s (got \(diff))")
    } else { expect(false, "in 2 hours should parse") }

    if let t = DateParser.parse("in 3 days") {
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: t)).day
        expectEqual(days, 3, "in 3 days is +3 days")
    } else { expect(false, "in 3 days should parse") }

    if let fri = DateParser.parse("friday") {
        expectEqual(cal.component(.weekday, from: fri), 6, "friday is weekday 6")
        expect(fri > Date(), "bare weekday is in the future")
        expectEqual(cal.component(.hour, from: fri), 9, "bare weekday defaults to 9am")
        expectEqual(cal.component(.minute, from: fri), 0, "bare weekday defaults to :00")
    } else { expect(false, "friday should parse") }

    if let mon = DateParser.parse("next monday") {
        expectEqual(cal.component(.weekday, from: mon), 2, "next monday is weekday 2")
    } else { expect(false, "next monday should parse") }

    // "friday noon" → the applyTime keyword shortcut must resolve to friday
    // at 12:00, not fall through to the malformed-numeric path.
    if let fnoon = DateParser.parse("friday noon") {
        expectEqual(cal.component(.weekday, from: fnoon), 6, "friday noon is on friday")
        expectEqual(cal.component(.hour, from: fnoon), 12, "friday noon is hour 12")
        expectEqual(cal.component(.minute, from: fnoon), 0, "friday noon is minute 0")
    } else { expect(false, "friday noon should parse") }

    // Other applyTime keywords
    if let feod = DateParser.parse("friday eod") {
        expectEqual(cal.component(.hour, from: feod), 17, "friday eod is hour 17")
    } else { expect(false, "friday eod should parse") }

    if let ttonight = DateParser.parse("tomorrow tonight") {
        expectEqual(cal.component(.hour, from: ttonight), 21, "tomorrow tonight is hour 21")
    } else { expect(false, "tomorrow tonight should parse") }

    if let mmorning = DateParser.parse("monday morning") {
        expectEqual(cal.component(.hour, from: mmorning), 9, "monday morning is hour 9")
    } else { expect(false, "monday morning should parse") }

    if let taft = DateParser.parse("tomorrow afternoon") {
        expectEqual(cal.component(.hour, from: taft), 14, "tomorrow afternoon is hour 14")
    } else { expect(false, "tomorrow afternoon should parse") }

    // Malformed weekday suffix must return nil rather than silently falling
    // back to the weekday's default 9am — otherwise typos like `friday abc`
    // or out-of-range times like `friday 25pm` / `friday 9:99` would land
    // tasks on a date the user didn't intend without any signal.
    expect(DateParser.parse("friday abc") == nil,
           "friday + malformed suffix returns nil (not friday 9am)")
    expect(DateParser.parse("friday 25pm") == nil,
           "friday + out-of-range hour returns nil (not friday 9am)")
    expect(DateParser.parse("friday 9:99") == nil,
           "friday + out-of-range minute returns nil (not friday 9am)")
}

// MARK: - Recurrence

func testRecurrence() {
    var comps = DateComponents()
    comps.year = 2026; comps.month = 1; comps.day = 15; comps.hour = 10
    let base = cal.date(from: comps)!

    let daily = Recurrence(frequency: .daily, interval: 2, endDate: nil)
    expectEqual(daily.nextDueDate(from: base), cal.date(byAdding: .day, value: 2, to: base), "daily/2 → +2 days")

    let weekly = Recurrence(frequency: .weekly, interval: 1, endDate: nil)
    expectEqual(weekly.nextDueDate(from: base), cal.date(byAdding: .day, value: 7, to: base), "weekly/1 → +7 days")

    let monthly = Recurrence(frequency: .monthly, interval: 1, endDate: nil)
    if let next = monthly.nextDueDate(from: base) {
        expectEqual(cal.component(.month, from: next), 2, "monthly/1 → February")
    } else { expect(false, "monthly should produce a date") }

    // endDate cutoff: next occurrence is beyond the end date → nil
    let capped = Recurrence(frequency: .weekly, interval: 1, endDate: cal.date(byAdding: .day, value: 3, to: base))
    expect(capped.nextDueDate(from: base) == nil, "recurrence past endDate → nil")

    // Interval must clamp to >= 1 — otherwise a zero/negative interval would
    // spawn an identical date forever (or move backwards in time), turning a
    // recurring task into a soft infinite loop after each completion.
    let zero = Recurrence(frequency: .daily, interval: 0, endDate: nil)
    expectEqual(zero.nextDueDate(from: base), cal.date(byAdding: .day, value: 1, to: base),
                "daily/0 clamps to +1 day (not zero)")
    let negative = Recurrence(frequency: .weekly, interval: -3, endDate: nil)
    expectEqual(negative.nextDueDate(from: base), cal.date(byAdding: .day, value: 7, to: base),
                "weekly/-3 clamps to +1 week (not backwards)")
    let negMonth = Recurrence(frequency: .monthly, interval: -1, endDate: nil)
    if let n = negMonth.nextDueDate(from: base) {
        expect(n > base, "monthly/-1 clamps forward (never before base)")
    } else { expect(false, "monthly/-1 should still produce a date") }
}

// MARK: - DueDateFormatter

func testDueDateFormatter() {
    let today = cal.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!
    expect(DueDateFormatter.format(today).contains("今天"), "today is labeled Today")

    let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
    expect(DueDateFormatter.format(tomorrow).contains("明天"), "tomorrow is labeled Tomorrow")
}

// MARK: - Color(hex:)

func rgba(_ c: Color) -> (r: Double, g: Double, b: Double, a: Double) {
    let ns = NSColor(c).usingColorSpace(.sRGB) ?? NSColor(c)
    return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent), Double(ns.alphaComponent))
}

func testColorHex() {
    let red = rgba(Color(hex: "#FF0000"))
    expect(abs(red.r - 1) < 0.02 && red.g < 0.02 && red.b < 0.02, "#FF0000 is red")

    let short = rgba(Color(hex: "0F0"))
    expect(short.g > 0.95 && short.r < 0.05, "#0F0 shorthand expands to green")

    let alpha = rgba(Color(hex: "#00FF0080"))
    expect(abs(alpha.a - 0.5) < 0.02, "#RRGGBBAA alpha ≈ 0.5 (got \(alpha.a))")

    let invalid = rgba(Color(hex: "nothex"))
    expect(abs(invalid.r - 0.6) < 0.02 && abs(invalid.g - 0.6) < 0.02, "invalid hex falls back to gray")
}

// MARK: - Hotkey modifier mapping

func testHotkeyMapping() {
    // ⌘⇧ → command + shift
    let cmdShift = HotkeyMapping.cocoaModifiers(fromCarbon: UInt32(cmdKey | shiftKey))
    expect(cmdShift.contains(.command), "cmdKey maps to .command")
    expect(cmdShift.contains(.shift), "shiftKey maps to .shift")
    expect(!cmdShift.contains(.option), "option absent when not set")
    expect(!cmdShift.contains(.control), "control absent when not set")

    // ⌃⌥ → control + option
    let ctrlOpt = HotkeyMapping.cocoaModifiers(fromCarbon: UInt32(controlKey | optionKey))
    expect(ctrlOpt.contains(.control), "controlKey maps to .control")
    expect(ctrlOpt.contains(.option), "optionKey maps to .option")
    expect(!ctrlOpt.contains(.command), "command absent when not set")

    // empty mask → no flags
    expect(HotkeyMapping.cocoaModifiers(fromCarbon: 0).isEmpty, "zero mask maps to empty flags")

    // all four set
    let all = HotkeyMapping.cocoaModifiers(fromCarbon: UInt32(cmdKey | shiftKey | optionKey | controlKey))
    expect(all.contains(.command) && all.contains(.shift) && all.contains(.option) && all.contains(.control),
           "all four Carbon modifiers map to all four Cocoa flags")
}

// MARK: - Dark-mode label color adaptation

func testColorAdaptation() {
    // The Midnight theme is always dark regardless of system appearance, so we
    // can exercise the dark-mode branch deterministically (no NSApp dependency).
    let midnight = AppTheme.midnight.rawValue

    func luminance(_ t: (r: Double, g: Double, b: Double, a: Double)) -> Double {
        0.299 * t.r + 0.587 * t.g + 0.114 * t.b
    }

    // A dark label (Graphite) must be lightened so it stays legible on a dark surface.
    let graphite = Color(hex: "#374151")
    let lifted = graphite.adaptedForCurrentScheme(themeRaw: midnight)
    expect(luminance(rgba(lifted)) > luminance(rgba(graphite)) + 0.05,
           "dark label is lightened in dark mode")

    // A bright label (Yellow) is already legible and must be returned unchanged.
    let yellow = Color(hex: "#EAB308")
    let y0 = rgba(yellow)
    let y1 = rgba(yellow.adaptedForCurrentScheme(themeRaw: midnight))
    expect(abs(y1.r - y0.r) < 0.01 && abs(y1.g - y0.g) < 0.01 && abs(y1.b - y0.b) < 0.01,
           "bright label is unchanged in dark mode")
}

// MARK: - MatrixLayout

func testMatrixLayout() {
    let size = CGSize(width: 200, height: 200)
    let seeds = Array(repeating: CGPoint(x: 0.5, y: 0.5), count: 5)
    let positions = MatrixLayout.resolvePositions(seeds: seeds, in: size, maxChars: 6, lineCount: 1)

    expectEqual(positions.count, 5, "resolver returns one position per seed")

    let pill = MatrixLayout.pillSize(maxChars: 6, lineCount: 1, in: size.width)
    expect(pill.width > 0 && pill.height > 0, "pillSize is positive")

    // All centers within bounds.
    for p in positions {
        expect(p.x >= pill.width / 2 - 0.001 && p.x <= size.width - pill.width / 2 + 0.001
               && p.y >= pill.height / 2 - 0.001 && p.y <= size.height - pill.height / 2 + 0.001,
               "pill center stays inside the box")
    }

    // No two inflated rects intersect (the whole point of the resolver).
    func rect(_ p: CGPoint) -> CGRect {
        CGRect(x: p.x - pill.width / 2 - 2, y: p.y - pill.height / 2 - 2,
               width: pill.width + 4, height: pill.height + 4)
    }
    for i in 0..<positions.count {
        for j in (i + 1)..<positions.count {
            expect(!rect(positions[i]).intersects(rect(positions[j])), "pills \(i) and \(j) do not overlap")
        }
    }

    // M02: releasing or reopening a pill at the top must leave the title/badge clear.
    let quadrantSize = CGSize(width: 184, height: 140)
    for lines in 1...3 {
        let testPill = MatrixLayout.pillSize(maxChars: 20, lineCount: lines, in: quadrantSize.width)
        let released = MatrixLayout.clampedPosition(CGPoint(x: 92, y: -20), in: quadrantSize, maxChars: 20, lineCount: lines)
        let restored = MatrixLayout.resolvePositions(seeds: [CGPoint(x: 0.5, y: 0)], in: quadrantSize, maxChars: 20, lineCount: lines)[0]
        expect(released.y - testPill.height / 2 >= 32, "top release keeps header and gap clear for \(lines) lines")
        expectEqual(restored, released, "restored and released top positions share safe bounds")
        let bottom = MatrixLayout.clampedPosition(CGPoint(x: 500, y: 500), in: quadrantSize, maxChars: 20, lineCount: lines)
        expect(bottom.x + testPill.width / 2 <= quadrantSize.width - 4 && bottom.y + testPill.height / 2 <= quadrantSize.height - 4,
               "opposite edges keep the entire pill inside")
    }
    // M03: use the actual released point, including the reproduced right-column move.
    expectEqual(MatrixLayout.dropTarget(from: .schedule, releasePoint: CGPoint(x: 60, y: 214), in: quadrantSize), .quadrant(.eliminate),
                "right column release in lower quadrant cannot fling to unassigned")
    expectEqual(MatrixLayout.dropTarget(from: .doFirst, releasePoint: CGPoint(x: 282, y: 70), in: quadrantSize), .quadrant(.schedule), "horizontal crossing")
    expectEqual(MatrixLayout.dropTarget(from: .doFirst, releasePoint: CGPoint(x: 280, y: 214), in: quadrantSize), .quadrant(.eliminate), "diagonal crossing")
    expectEqual(MatrixLayout.dropTarget(from: .eliminate, releasePoint: CGPoint(x: 90, y: -74), in: quadrantSize), .quadrant(.schedule), "return to upper quadrant")
    expectEqual(MatrixLayout.dropTarget(from: .doFirst, releasePoint: CGPoint(x: 90, y: 335), in: quadrantSize), .unassigned, "release below whole grid clears assignment")
    expectEqual(MatrixLayout.dropTarget(from: .eliminate, releasePoint: CGPoint(x: 90, y: 190), in: quadrantSize), .unassigned, "bottom row release into unassigned strip")
    expectEqual(MatrixLayout.dropTarget(from: .doFirst, releasePoint: CGPoint(x: -20, y: 40), in: quadrantSize), .quadrant(.doFirst), "outside edge without a neighbor stays assigned")

    expect(MatrixLayout.resolvePositions(seeds: [], in: size, maxChars: 6, lineCount: 1).isEmpty,
           "empty seeds → empty result")
    expect(MatrixLayout.resolvePositions(seeds: seeds, in: .zero, maxChars: 6, lineCount: 1).allSatisfy { $0 == .zero },
           "zero size → all .zero")
}

// MARK: - TodoItem Codable

func testTodoItemCodable() {
    var item = TodoItem(title: "Round trip", notes: "n", priority: .high)
    item.sortOrder = 7
    item.labelIds = [UUID()]
    let data = try! JSONEncoder().encode(item)
    let decoded = try! JSONDecoder().decode(TodoItem.self, from: data)
    expectEqual(decoded, item, "TodoItem survives an encode/decode round trip")

    // Backward compatibility: a minimal payload missing optional fields.
    let minimal = """
    {"id":"\(UUID().uuidString)","title":"Old","notes":"","createdAt":0,"priorityRaw":1,"reminderOffsetRaw":3}
    """.data(using: .utf8)!
    do {
        let old = try JSONDecoder().decode(TodoItem.self, from: minimal)
        expectEqual(old.sortOrder, 0, "missing sortOrder defaults to 0")
        expect(old.labelIds.isEmpty, "missing labelIds defaults to []")
        expect(old.dueDate == nil, "missing dueDate decodes as nil")
    } catch {
        expect(false, "minimal legacy payload should decode: \(error)")
    }

    // Even-more-legacy payload that OMITS notes entirely — historically this
    // failed to decode, forcing the store to drop the task on load.
    let noNotes = """
    {"id":"\(UUID().uuidString)","title":"Bare","createdAt":0,"priorityRaw":0,"reminderOffsetRaw":0}
    """.data(using: .utf8)!
    do {
        let decoded = try JSONDecoder().decode(TodoItem.self, from: noNotes)
        expectEqual(decoded.notes, "", "missing notes defaults to empty string")
        expectEqual(decoded.title, "Bare", "title still decoded when notes missing")
    } catch {
        expect(false, "legacy TodoItem without notes must decode: \(error)")
    }

    // Even the title can be missing on the oldest exports — decode must not
    // fail; we fall back to "Untitled" (not empty) so the row remains
    // visible and selectable in the UI.
    let noTitle = """
    {"id":"\(UUID().uuidString)","notes":"","createdAt":0,"priorityRaw":1,"reminderOffsetRaw":3}
    """.data(using: .utf8)!
    do {
        let decoded = try JSONDecoder().decode(TodoItem.self, from: noTitle)
        expectEqual(decoded.title, "Untitled", "missing title defaults to 'Untitled'")
    } catch {
        expect(false, "legacy TodoItem without title must decode: \(error)")
    }
}

// MARK: - DocketExport schema version

func testDocketExport() {
    let withVersion = """
    {"schemaVersion":1,"lists":[],"labels":[],"tasks":[]}
    """.data(using: .utf8)!
    let a = try! JSONDecoder().decode(DocketExport.self, from: withVersion)
    expectEqual(a.schemaVersion, 1, "schemaVersion decodes when present")

    let withoutVersion = """
    {"lists":[],"labels":[],"tasks":[]}
    """.data(using: .utf8)!
    let b = try! JSONDecoder().decode(DocketExport.self, from: withoutVersion)
    expect(b.schemaVersion == nil, "schemaVersion absent → nil (backward compatible)")
}

// MARK: - ColorPalette + Color.toHex round-trip

func testColorPalette() {
    // Every preset is a valid hex string and round-trips through Color(hex:) → toHex().
    for preset in ColorPalette.presets {
        let c = Color(hex: preset.hex)
        if let back = c.toHex() {
            expectEqual(back.uppercased(), preset.hex.uppercased(),
                        "palette '\(preset.name)' (\(preset.hex)) round-trips through Color↔hex")
        } else {
            expect(false, "palette '\(preset.name)' (\(preset.hex)) failed toHex()")
        }
    }

    expectEqual(ColorPalette.presets.count, 20, "palette has exactly 20 colors")

    // Deterministic fallback is stable across calls and stays inside the palette.
    let key = UUID().uuidString
    let a = ColorPalette.deterministic(for: key)
    let b = ColorPalette.deterministic(for: key)
    expectEqual(a, b, "deterministic() is stable for the same key")
    expect(ColorPalette.presets.contains(where: { $0.hex == a }),
           "deterministic() returns a palette member")

    // Different keys mostly map to different colors (sanity — not a strict guarantee).
    let distinct = Set((0..<50).map { ColorPalette.deterministic(for: "key-\($0)") })
    expect(distinct.count >= 10, "deterministic() spreads across the palette (got \(distinct.count) distinct)")
}

// MARK: - TaskList color resolution + Codable backwards compatibility

func testTaskListColor() {
    // 1. A list without a stored colorHex still has a (deterministic) color.
    let listA = TaskList(name: "Inbox")
    let resolvedA = listA.resolvedHex
    expect(ColorPalette.presets.contains(where: { $0.hex == resolvedA }),
           "list without colorHex resolves to a palette color")
    expectEqual(listA.resolvedHex, resolvedA, "resolvedHex is stable for the same list instance")

    // 2. A list with a stored colorHex returns it verbatim.
    var listB = TaskList(name: "Work", colorHex: "#FF00AA")
    expectEqual(listB.resolvedHex, "#FF00AA", "stored colorHex wins over fallback")
    listB.colorHex = nil
    expect(ColorPalette.presets.contains(where: { $0.hex == listB.resolvedHex }),
           "clearing colorHex falls back to a palette color")

    // 3. Legacy lists.json (without the colorHex field) decodes cleanly.
    let id = UUID().uuidString
    let createdAt = Date().timeIntervalSinceReferenceDate
    let legacyJSON = """
    {"id":"\(id)","name":"Legacy","createdAt":\(createdAt),"isDefault":false}
    """.data(using: .utf8)!
    do {
        let decoded = try JSONDecoder().decode(TaskList.self, from: legacyJSON)
        expect(decoded.colorHex == nil, "legacy lists.json decodes with nil colorHex")
        expect(ColorPalette.presets.contains(where: { $0.hex == decoded.resolvedHex }),
               "legacy list still resolves to a palette color")
    } catch {
        expect(false, "legacy lists.json should decode: \(error)")
    }

    // 4. Codable round-trip preserves a stored colorHex.
    let original = TaskList(name: "Travel", colorHex: "#0EA5E9")
    let data = try! JSONEncoder().encode(original)
    let round = try! JSONDecoder().decode(TaskList.self, from: data)
    expectEqual(round.colorHex, "#0EA5E9", "TaskList.colorHex survives encode/decode")
    expectEqual(round.name, "Travel", "TaskList.name survives encode/decode")
}

// MARK: - IconPalette

func testIconPalette() {
    expectEqual(IconPalette.presets.count, 15, "icon palette has exactly 15 icons")
    let unique = Set(IconPalette.presets)
    expectEqual(unique.count, IconPalette.presets.count, "all icons are distinct")
    expect(IconPalette.presets.contains(IconPalette.defaultIcon),
           "defaultIcon is in the preset list")

    // Every preset has a non-empty localized display name.
    for icon in IconPalette.presets {
        let name = IconPalette.displayName(icon)
        expect(!name.isEmpty, "displayName for '\(icon)' is non-empty")
    }

    // Unknown icon falls back to its raw symbol name.
    let unknown = "this.is.not.a.preset"
    expectEqual(IconPalette.displayName(unknown), unknown,
                "displayName falls back to the raw symbol for unknown icons")
}


func testGoalBoard() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        calendar.date(from: DateComponents(year:y,month:m,day:d,hour:h))!
    }
    let now = date(2026,9,8,12)
    var monthly = TodoItem(title: "月度发布", dueDate: date(2026,9,30))
    monthly.goalPeriod = .month
    monthly.createdAt = now
    var annual = TodoItem(title: "年度方向", dueDate: date(2026,12,31))
    annual.goalPeriod = .year; annual.isPinned = true
    var other = TodoItem(title: "长期方向"); other.goalPeriod = .longTerm
    expect(GoalFilter.month.includes(monthly, now:now, calendar:calendar), "current month goal is visible in month filter")
    expect(!GoalFilter.year.includes(monthly, now:now, calendar:calendar), "month and annual horizons remain separate")
    expect(GoalFilter.year.includes(annual, now:now, calendar:calendar), "annual goal is visible in year filter")
    expect(GoalFilter.longTerm.includes(other, now:now, calendar:calendar), "undated long-term goal stays visible")
    expect(!GoalFilter.month.includes(monthly, now:date(2026,10,1), calendar:calendar), "past month stays out of current-month filter")
    expect(GoalFilter.all.includes(monthly, now:date(2026,10,1), calendar:calendar), "past goal remains accessible in all")
    expectEqual(GoalPeriod.end(of:.month,from:date(2028,2,1),calendar:calendar),date(2028,2,29),"leap-year month end")
    expectEqual(GoalPeriod.end(of:.year,from:now,calendar:calendar),date(2026,12,31),"year end")
    expectEqual(GoalPeriod.end(of:.quarter,from:now,calendar:calendar),date(2026,9,30),"quarter end")
    monthly.dueDate = date(2026,9,8,2)
    expect(!monthly.isOverdue(at:now,calendar:calendar), "date-only target is not overdue during its final day")
    monthly.hasDueTime = true
    expect(monthly.isOverdue(at:now,calendar:calendar), "explicit due time is honored")
    monthly.hasDueTime = false
    expect(monthly.isOverdue(at:date(2026,9,9),calendar:calendar), "date-only target expires on next day")
    expectEqual(DueDateFormatter.format(date(2026,9,30,2),now:now,calendar:calendar),"9月30日","date-only display hides inherited clock")
    expect(DueDateFormatter.format(date(2026,9,30,2),hasTime:true,now:now,calendar:calendar).contains("02:00"), "explicit 24-hour time")
    expectEqual(DueDateFormatter.remaining(date(2026,9,30),now:now,calendar:calendar),"还剩 22 天","calendar-day countdown")
    expectEqual(GoalBoardRules.ordered([monthly,annual,other]).first?.id,annual.id,"pin outranks manual order")
    expectEqual(GoalBoardRules.featured(in:[monthly,annual],preferredID:nil)?.id,annual.id,"first pin appears in menu bar")
    monthly.isPinned = true
    expectEqual(GoalBoardRules.featured(in:[monthly,annual],preferredID:annual.id.uuidString)?.id,annual.id,"explicit primary goal survives other pins")
    annual.completedAt = now
    expectEqual(GoalBoardRules.featured(in:[monthly,annual],preferredID:annual.id.uuidString)?.id,monthly.id,"completed primary falls back to next pin")
    expect(GoalBoardRules.featured(in:[monthly],preferredID:"none") == nil,"explicit menu title off state")
    expectEqual(GoalBoardRules.menuTitle("年度目标"),"年度目标","short title not truncated")
    let long = String(repeating:"👨‍👩‍👧‍👦长期方向",count:12)
    let shortened = GoalBoardRules.menuTitle(long)
    expect(shortened.hasSuffix("…") && shortened.count <= 30,"long menu title is bounded without splitting graphemes")
    expectEqual(GoalBoardRules.panelSize(availableHeight: 900), NSSize(width: 408, height: 560), "one panel frame for every route")
    expectEqual(GoalBoardRules.panelSize(availableHeight: 500), NSSize(width: 408, height: 440), "small display reserves room outside the panel")
    do {
        var payload = try JSONSerialization.jsonObject(with:JSONEncoder().encode(monthly)) as! [String:Any]
        payload.removeValue(forKey:"goalPeriod");payload.removeValue(forKey:"isPinned");payload.removeValue(forKey:"hasDueTime")
        let legacy = try JSONDecoder().decode(TodoItem.self,from:JSONSerialization.data(withJSONObject:payload))
        expectEqual(legacy.id,monthly.id,"legacy identity preserved")
        expectEqual(legacy.dueDate,monthly.dueDate,"legacy timestamp preserved exactly")
        expect(!legacy.hasDueTime && !legacy.isPinned,"legacy safe metadata defaults")
        let roundtrip = try JSONDecoder().decode(TodoItem.self,from:JSONEncoder().encode(monthly))
        expectEqual(roundtrip,monthly,"pin, horizon and precision survive restart serialization")
    } catch { expect(false,"goal schema roundtrip: \(error)") }
}

func testGoalDeadlineEdgeCases() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 12))!
    var goal = TodoItem(title: "无硬截止日的月度目标")
    goal.createdAt = now
    goal.goalPeriod = .month
    expect(GoalFilter.month.includes(goal, now: now, calendar: calendar), "monthly goal remains visible after removing its deadline")
    goal.goalPeriod = .year
    expect(GoalFilter.year.includes(goal, now: now, calendar: calendar), "annual goal without a deadline belongs to its creation year")
    let nextYear = calendar.date(byAdding: .year, value: 1, to: now)!
    expect(!GoalFilter.year.includes(goal, now: nextYear, calendar: calendar), "undated yearly goal does not leak into future years")
    expect(GoalFilter.all.includes(goal, now: nextYear, calendar: calendar), "older undated annual goal remains accessible")
    goal.dueDate = now; goal.hasDueTime = true; goal.isPinned = true
    let annual = GoalScheduleRules.changingPeriod(goal, to: .year, now: now, calendar: calendar)
    expectEqual(calendar.component(.month, from: annual.dueDate!), 12, "switching to annual selects December")
    expectEqual(calendar.component(.day, from: annual.dueDate!), 31, "switching to annual selects final day")
    expect(!annual.hasDueTime, "switching periods does not silently schedule a midnight deadline")
    expectEqual(annual.id, goal.id, "period changes preserve goal identity")
    expect(annual.isPinned, "period changes preserve the pin")
    let longTerm = GoalScheduleRules.changingPeriod(goal, to: .longTerm, now: now, calendar: calendar)
    expect(longTerm.dueDate == nil && !longTerm.hasDueTime, "long-term reset removes deadline and time precision together")
    expectEqual(DueDateFormatter.remaining(now.addingTimeInterval(5400), hasTime: true, now: now, calendar: calendar), "还剩 1 小时", "precise deadline shows remaining hours")
    expectEqual(DueDateFormatter.remaining(now.addingTimeInterval(-600), hasTime: true, now: now, calendar: calendar), "已过 10 分钟", "same-day expired time must not read today due")
    expectEqual(DueDateFormatter.remaining(now.addingTimeInterval(30), hasTime: true, now: now, calendar: calendar), "即将截止", "less than a minute does not show zero minutes")
    expectEqual(DueDateFormatter.remaining(now.addingTimeInterval(-30), hasTime: true, now: now, calendar: calendar), "刚刚超时", "precise expiration transition")
    expectEqual(DueDateFormatter.remaining(now.addingTimeInterval(-600), now: now, calendar: calendar), "今天截止", "date-only deadlines retain whole-day semantics")
}


func testGoalDateInput() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))! }
    let now = date(2026, 12, 30, 23)
    for (input, expected) in [("今天", date(2026,12,30)), ("后天", date(2027,1,1)), ("下周", date(2027,1,6)), ("3天后", date(2027,1,2)), ("本月底", date(2026,12,31)), ("下月底", date(2027,1,31)), ("今年底", date(2026,12,31)), ("10月15日", date(2026,10,15)), ("2028-02-29", date(2028,2,29)), ("2027年1月8日", date(2027,1,8))] {
        expectEqual(GoalDateParser.parse(input, now: now, calendar: calendar), expected, "Chinese date input: \(input)")
    }
    for invalid in ["2027-02-29", "2026-02-30", "2026-13-1", "2026-0-2", "2026-2-0", "2月30日", "某一天", "", "2027-01-08abc"] {
        expect(GoalDateParser.parse(invalid, now: now, calendar: calendar) == nil, "reject invalid date: \(invalid)")
    }
    var goal = TodoItem(title: "长期目标", dueDate: date(2026,12,30,15))
    goal.goalPeriod = .longTerm; goal.isPinned = true; goal.hasDueTime = true
    let changed = GoalScheduleRules.changingDate(goal, to: date(2027,1,8), calendar: calendar)
    expectEqual(changed.goalPeriod, .longTerm, "date choice does not change horizon")
    expectEqual(changed.dueDate, date(2027,1,8,15), "date choice preserves explicit reminder time")
    expectEqual(changed.id, goal.id, "date choice preserves identity")
    expect(changed.isPinned, "date choice preserves pin")
    let cleared = GoalScheduleRules.changingDate(goal, to: nil, calendar: calendar)
    expect(cleared.dueDate == nil && !cleared.hasDueTime && cleared.recurrence == nil, "clear removes date and dependent scheduling")
    expectEqual(cleared.goalPeriod, .longTerm, "clear date retains horizon")
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let spring = date(2026,3,7,15)
    expectEqual(GoalDateParser.parse("明天", now: spring, calendar: calendar), date(2026,3,8), "relative dates follow local calendar over DST")
}

func testGoalImportPlan() {
    let base = TaskList(name: "月度", isDefault: true)
    var incomingList = TaskList(name: "月度", remindersCalendarId: "external-calendar")
    let incomingLabel = TaskLabel(name: "产品", listId: incomingList.id)
    var goal = TodoItem(title: "发布课程")
    goal.listId = incomingList.id; goal.labelIds = [incomingLabel.id]; goal.reminderId = "external-reminder"
    func plan(_ export: DocketExport, existing: [TodoItem] = []) throws -> GoalImportPlan {
        try GoalImportPlan(data: JSONEncoder().encode(export), lists: [base], labels: [], tasks: existing, activeListID: base.id, supportedVersion: 2)
    }
    do {
        let exported = DocketExport(schemaVersion: 1, lists: [incomingList], labels: [incomingLabel], tasks: [goal])
        let result = try plan(exported)
        expect(result.lists.isEmpty, "import merges same-name lists")
        expectEqual(result.tasks.first?.listId, base.id, "import remaps task to surviving list")
        expectEqual(result.labels.first?.listId, base.id, "import remaps label to surviving list")
        expectEqual(result.tasks.first?.labelIds, [incomingLabel.id], "import retains label relationship")
        expect(result.tasks.first?.reminderId == nil, "import cannot adopt external Apple reminder binding")
        let duplicate = try plan(exported, existing: [goal])
        expect(duplicate.tasks.isEmpty && duplicate.skipped == 1, "import skips existing goals")
        incomingList.name = "年度"
        let newList = try plan(DocketExport(lists: [incomingList], labels: [], tasks: [goal]))
        expect(newList.lists.first?.remindersCalendarId == nil, "import cannot adopt external calendar binding")
        expect(newList.tasks.first?.labelIds.isEmpty == true, "import strips orphan labels")
        do { _ = try plan(DocketExport(schemaVersion: 999, lists: [], labels: [], tasks: [])); expect(false, "future schema rejected") }
        catch { expect(true, "future schema rejected before mutation") }
        do { _ = try plan(DocketExport(lists: [], labels: [], tasks: [goal, goal])); expect(false, "duplicate UUID rejected") }
        catch { expect(true, "duplicate UUID rejected before mutation") }
        do { _ = try GoalImportPlan(data: Data("{}".utf8), lists: [base], labels: [], tasks: [], activeListID: base.id, supportedVersion: 2); expect(false, "invalid JSON shape rejected") }
        catch { expect(true, "invalid JSON shape rejected before mutation") }
        let legacy = try GoalImportPlan(data: JSONEncoder().encode([goal]), lists: [base], labels: [], tasks: [], activeListID: base.id, supportedVersion: 2)
        expectEqual(legacy.tasks.first?.listId, base.id, "legacy import uses current list")
    } catch { expect(false, "valid backup imports: \(error)") }
}

func testWeeklyGoals() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    calendar.firstWeekday = 1 // User locale must not turn a goal week into Sunday–Saturday.
    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    let now = date(2026, 9, 8, 12)
    let source = TodoItem(title: "周目标", notes: "保留原描述", steps: [GoalStep(title: "访谈")])
    let weekly = GoalScheduleRules.changingPeriod(source, to: .week, now: now, calendar: calendar)
    expectEqual(weekly.dueDate, date(2026, 9, 13), "weekly deadline defaults to Sunday at date-only midnight")
    expectEqual(weekly.goalPeriod, .week, "weekly period is explicit")
    expectEqual(weekly.notes, source.notes, "changing to week preserves goal description")
    expectEqual(weekly.steps, source.steps, "changing to week preserves checklist")
    expect(!weekly.hasDueTime, "weekly deadlines do not invent a precise midnight alarm")
    expect(GoalFilter.week.includes(weekly, now: now, calendar: calendar), "this-week filter includes Sunday deadline")
    expect(GoalFilter.week.includes(weekly, now: date(2026, 9, 13, 23), calendar: calendar), "Sunday stays in same week")
    expect(!GoalFilter.week.includes(weekly, now: date(2026, 9, 14), calendar: calendar), "previous week excluded exactly on Monday")
    expect(GoalFilter.all.includes(weekly, now: date(2026, 9, 14), calendar: calendar), "older weekly goals remain in all")
    expect(!GoalFilter.month.includes(weekly, now: now, calendar: calendar), "weekly goals are not mixed into month classification")
    var crossYear = weekly
    crossYear.dueDate = date(2027, 1, 3)
    expect(GoalFilter.week.includes(crossYear, now: date(2026, 12, 28), calendar: calendar), "cross-year Sunday matches December Monday")
    expect(GoalFilter.week.includes(crossYear, now: date(2027, 1, 1), calendar: calendar), "same ISO week remains together after year change")
    crossYear.dueDate = date(2027, 1, 4)
    expect(!GoalFilter.week.includes(crossYear, now: date(2027, 1, 3), calendar: calendar), "next Monday not included at half-open boundary")
    var undated = weekly; undated.dueDate = nil; undated.createdAt = now
    expect(GoalFilter.week.includes(undated, now: now, calendar: calendar), "undated weekly goal uses creation week")
    expectEqual(GoalDateParser.parse("本周末", now: now, calendar: calendar), date(2026, 9, 13), "weekly quick text selects Sunday")
    expectEqual(GoalDateParser.parse("下周末", now: now, calendar: calendar), date(2026, 9, 20), "next weekend uses next goal week")
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    expectEqual(GoalPeriod.end(of: .weekOfYear, from: date(2026, 3, 4), calendar: calendar), date(2026, 3, 8), "spring DST week ends on local Sunday")
    expectEqual(GoalPeriod.end(of: .weekOfYear, from: date(2026, 10, 28), calendar: calendar), date(2026, 11, 1), "autumn DST week ends on local Sunday")
    let spring = GoalPeriod.weekInterval(containing: date(2026, 3, 4), calendar: calendar)
    expectEqual(spring.duration, 167 * 3600, "week boundaries follow local DST rather than 168-hour arithmetic")
}

func testGoalSteps() {
    let completed = GoalStep(title: "联系三位客户", isCompleted: true)
    let draft = TodoItem(title: "用户研究", notes: "原有自由文字\n完整保留", steps: [completed, GoalStep(title: "写出结论")])
    do {
        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(TodoItem.self, from: data)
        expectEqual(decoded, draft, "goal and step identifiers, order, completion round trip")
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy.removeValue(forKey: "steps")
        let old = try JSONDecoder().decode(TodoItem.self, from: JSONSerialization.data(withJSONObject: legacy))
        expect(old.steps.isEmpty, "legacy goal decodes without checklist migration")
        expectEqual(old.notes, draft.notes, "legacy description is not transformed into guessed steps")
        let clean = GoalStep.normalized([GoalStep(title: " \n "), GoalStep(title: "  第一项  "), completed, completed])
        expectEqual(clean.count, 3, "empty draft rows do not become stored steps")
        expectEqual(clean.first?.title, "第一项", "step whitespace trimmed")
        expectEqual(Set(clean.map(\.id)).count, clean.count, "duplicate step identities repaired before a SwiftUI binding list")
        let next = completed.forNextOccurrence()
        expect(next.id != completed.id && !next.isCompleted && next.title == completed.title, "next recurrence has fresh unfinished steps")
        var weekly = draft; weekly.goalPeriod = .week
        expectEqual(try JSONDecoder().decode(TodoItem.self, from: JSONEncoder().encode(weekly)).goalPeriod, .week, "weekly period survives JSON round trip")
        let list = TaskList(name: "目标", isDefault: true)
        let plan = try GoalImportPlan(data: JSONEncoder().encode([draft]), lists: [list], labels: [], tasks: [], activeListID: list.id, supportedVersion: 2)
        expectEqual(plan.tasks.first?.steps, draft.steps, "backup import keeps checklist progress and order")
        var invalid = draft; invalid.steps.append(completed)
        do {
            _ = try GoalImportPlan(data: JSONEncoder().encode([invalid]), lists: [list], labels: [], tasks: [], activeListID: list.id, supportedVersion: 2)
            expect(false, "duplicate imported step IDs must fail")
        } catch { expect(true, "duplicate imported step IDs rejected before mutation") }
    } catch { expect(false, "checklist storage compatibility: \(error)") }
}

func testShortcutRecordingRules() {
    let flags: NSEvent.ModifierFlags = [.control, .option, .shift, .command, .capsLock, .numericPad]
    let carbon = HotkeyMapping.carbonModifiers(fromCocoa: flags)
    expectEqual(carbon, controlKey | optionKey | shiftKey | cmdKey, "capture retains exactly four hotkey modifiers")
    expectEqual(HotkeyMapping.cocoaModifiers(fromCarbon: UInt32(carbon)), [.control, .option, .shift, .command], "recorded modifier round trip")
    expect(HotkeyMapping.validationError(keyCode: kVK_ANSI_Q, modifiers: optionKey | controlKey) == nil, "custom key outside old presets accepted")
    expect(HotkeyMapping.validationError(keyCode: kVK_F12, modifiers: controlKey) == nil, "function-key combination accepted")
    expect(HotkeyMapping.validationError(keyCode: kVK_ANSI_Q, modifiers: 0) != nil, "plain typing cannot become a global shortcut")
    expect(HotkeyMapping.validationError(keyCode: kVK_ANSI_Q, modifiers: shiftKey) != nil, "shift-only typing is protected")
    expect(HotkeyMapping.validationError(keyCode: kVK_Space, modifiers: cmdKey) != nil, "Spotlight shortcut rejected explicitly")
    expect(HotkeyMapping.validationError(keyCode: kVK_Space, modifiers: controlKey | shiftKey) == nil, "existing Ctrl Shift Space remains valid")
    expect(HotkeyMapping.validationError(keyCode: -1, modifiers: cmdKey) != nil, "invalid key code rejected without UInt32 trap")
    expectEqual(HotkeyMapping.keyLabel(keyCode: kVK_F12), "F12", "function key displayed by name")
    expectEqual(HotkeyMapping.keyLabel(keyCode: kVK_LeftArrow), "←", "arrow displayed by symbol")
    expectEqual(HotkeyMapping.displayString(keyCode: kVK_ANSI_Q, modifiers: controlKey | optionKey, recordedLabel: "q"), "⌃⌥ Q", "arbitrary captured key uses its real label")
}

func testEditorNavigationIdentity() {
    let goal = TodoItem(title: "Same goal opened twice")
    let original = NavDestination.detail(goal)
    let reopened = NavDestination.detail(goal)
    expect(original.editorID != reopened.editorID, "same goal gets distinct navigation identities")
    expect(original != reopened, "duplicate goal visits are distinct SwiftUI destinations")
    let newA = NavDestination.create(), newB = NavDestination.create()
    expect(newA.editorID != newB.editorID, "each new draft gets its own navigation identity")
    var path: [NavDestination] = [original, .settings, .matrix, reopened]
    expectEqual(path.last?.editorID, reopened.editorID, "top editor owns save and escape")
    expect(path.last?.editorID != original.editorID, "hidden instance of same goal does not own keyboard command")
    path.removeLast()
    expect(path.last?.editorID == nil, "matrix cannot route editor save")
    expect(path.contains(where: \.isEditor), "closing settings keeps original editor route")
    path.removeLast(2)
    expectEqual(path.last?.editorID, original.editorID, "back navigation restores original editor identity")
    expectEqual(path.first, original, "original draft destination survives nested settings unchanged")
    expect(![NavDestination.settings, .advancedSettings, .completed, .matrix].contains(where: \.isEditor), "non-editor routes do not retain a phantom draft")
}

// MARK: - Run

testEditorNavigationIdentity()
testWeeklyGoals()
testGoalSteps()
testShortcutRecordingRules()

testGoalImportPlan()
testGoalBoard()
testGoalDateInput()
testGoalDeadlineEdgeCases()
testDateParser()
testRecurrence()
testDueDateFormatter()
testColorHex()
testHotkeyMapping()
testColorAdaptation()
testColorPalette()
testTaskListColor()
testIconPalette()
testMatrixLayout()
testTodoItemCodable()
testDocketExport()

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
