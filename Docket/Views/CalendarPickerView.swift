import SwiftUI

struct CalendarPickerView: View {
    @Binding var selectedDate: Date?
    @Binding var displayedMonth: Date
    var focusRequest = 0
    @Environment(\.polarisPalette) private var palette
    @FocusState private var focusedDate: Date?
    private let calendar = Calendar.current
    private var days: [Date?] {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
        let blanks: [Date?] = Array(repeating: nil, count: (calendar.component(.weekday, from: first) + 5) % 7)
        let monthDays = calendar.range(of: .day, in: .month, for: first)!.map { calendar.date(byAdding: .day, value: $0 - 1, to: first) }
        let visibleDays = blanks + monthDays
        return visibleDays + Array(repeating: nil, count: 42 - visibleDays.count)
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(displayedMonth.formatted(.dateTime.year().month(.wide).locale(DueDateFormatter.locale))).font(.system(size: 12.5, weight: .medium))
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 30, height: 30).contentShape(Rectangle()) }.accessibilityLabel("上个月")
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 30, height: 30).contentShape(Rectangle()) }.accessibilityLabel("下个月")
            }.buttonStyle(GoalControlStyle())
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).font(.system(size: 10.5)).foregroundStyle(palette.muted).frame(height: 21) }
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let selected = selectedDate.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
                        let today = calendar.isDateInToday(date)
                        Button { selectedDate = date } label: {
                            Text("\(calendar.component(.day, from: date))").font(.system(size: 12, weight: selected ? .medium : .regular))
                                .frame(width: 32, height: 30)
                                .foregroundStyle(selected ? palette.actionText : palette.ink)
                                .contentShape(Rectangle())
                                .background(Circle().fill(selected ? palette.action : .clear).frame(width: 26, height: 26))
                                .overlay(Circle().strokeBorder(today && !selected ? palette.accentInk : .clear, lineWidth: 1).frame(width: 26, height: 26))
                        }.buttonStyle(GoalControlStyle()).focusable().focused($focusedDate, equals: date)
                            .onKeyPress(.return) { selectedDate = date; return .handled }
                            .onKeyPress(.space) { selectedDate = date; return .handled }
                            .accessibilityLabel(date.formatted(.dateTime.year().month().day().locale(DueDateFormatter.locale)) + (today ? "，今天" : ""))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                    } else { Color.clear.frame(height: 30).accessibilityHidden(true) }
                }
            }.onMoveCommand(perform: moveFocus)
        }.onChange(of: focusRequest) { _, _ in
            let preferred = selectedDate ?? Date()
            focusedDate = calendar.isDate(preferred, equalTo: displayedMonth, toGranularity: .month)
                ? calendar.startOfDay(for: preferred)
                : calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
        }
    }
    private func shift(_ delta: Int) { displayedMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth }
    private func moveFocus(_ direction: MoveCommandDirection) {
        let offset: Int
        switch direction {
        case .left: offset = -1
        case .right: offset = 1
        case .up: offset = -7
        case .down: offset = 7
        default: return
        }
        let current = focusedDate ?? selectedDate.map { calendar.startOfDay(for: $0) }
            ?? calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
        guard let next = calendar.date(byAdding: .day, value: offset, to: current) else { return }
        if !calendar.isDate(next, equalTo: displayedMonth, toGranularity: .month) {
            displayedMonth = next
            DispatchQueue.main.async { focusedDate = next }
        } else { focusedDate = next }
    }
}
