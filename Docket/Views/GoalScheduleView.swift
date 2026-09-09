import SwiftUI
import AppKit

struct GoalScheduleView: View {
    @Binding var item: TodoItem
    let isActiveEditor: () -> Bool
    @Environment(PolarisPresentation.self) private var presentation
    @Environment(\.polarisPalette) private var palette
    @FocusState private var dateButtonFocused: Bool
    @State private var isVisible = false
    @State private var calendarOwnerID = UUID()
    @State private var calendarPopoverID: ObjectIdentifier?
    @State private var calendarOwner = CalendarPopoverOwner()
    @State private var inputOwner = PolarisFieldEditorOwner()
    @State private var focusGeneration = 0
    private var calendarPresented: Binding<Bool> {
        Binding(get: { isActiveEditor() && presentation.calendarOwnerID == calendarOwnerID }, set: { shown in
            if shown {
                if isActiveEditor() { presentation.presentCalendar(ownedBy: calendarOwnerID) }
            } else {
                inputOwner.invalidate()
                presentation.dismissCalendar(ownedBy: calendarOwnerID)
            }
        })
    }
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Text("周期").foregroundStyle(palette.secondary).frame(width: 52, alignment: .leading)
                Spacer(minLength: 0)
                Picker("目标周期", selection: Binding(get: { item.goalPeriod }, set: {
                    item = GoalScheduleRules.changingPeriod(item, to: $0)
                })) {
                    ForEach(GoalPeriod.allCases) { Text($0.shortTitle).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).controlSize(.small)
            }.frame(minHeight: 36)
            Button { calendarPresented.wrappedValue.toggle() } label: {
                GoalOptionLabel(title: "截止日期", value: item.dueDate.map { $0.formatted(.dateTime.year().month().day().locale(DueDateFormatter.locale)) } ?? "未设定")
            }.buttonStyle(GoalControlStyle()).focusable(isActiveEditor()).focused($dateButtonFocused).accessibilityLabel("截止日期")
                .onKeyPress(.space) { calendarPresented.wrappedValue = true; return .handled }
                .onKeyPress(.return) { calendarPresented.wrappedValue = true; return .handled }
                .popover(isPresented: calendarPresented, arrowEdge: .top) {
                    GoalDatePopover(value: item.dueDate, calendarOwnerID: calendarOwnerID,
                        inputOwner: inputOwner,
                        isActive: { isActiveEditor() && isVisible && presentation.calendarOwnerID == calendarOwnerID }) { date in
                        guard isActiveEditor() else { return }
                        item = GoalScheduleRules.changingDate(item, to: date)
                        presentation.dismissCalendar(ownedBy: calendarOwnerID)
                    }
                    .environment(\.polarisPalette, palette)
                    .environment(\.colorScheme, palette.isDark ? .dark : .light)
                    .background { CalendarPopoverAnchor(owner: calendarOwner).frame(width: 0, height: 0) }
                }
            if item.goalPeriod == .week {
                Text("周一至周日 · 默认周日截止")
                    .font(.system(size: 10.5)).foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.font(.system(size: 12.5))
        .onAppear { isVisible = true }
        .onChange(of: isActiveEditor()) { _, active in
            if !active {
                inputOwner.invalidate()
                focusGeneration &+= 1
                calendarPopoverID = nil
                dateButtonFocused = false
                presentation.dismissCalendar(ownedBy: calendarOwnerID)
            }
        }
        .onChange(of: presentation.calendarIsPresented) { _, shown in
            if shown {
                focusGeneration &+= 1
                calendarPopoverID = nil
                dateButtonFocused = false
            }
        }
        .onChange(of: presentation.calendarOwnerID) { _, owner in
            if owner != calendarOwnerID { inputOwner.invalidate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didShowNotification)) { notification in
            guard isActiveEditor(), isVisible, presentation.calendarIsPresented,
                  let popover = notification.object as? NSPopover,
                  let content = popover.contentViewController?.view,
                  calendarOwner.view?.isDescendant(of: content) == true else { return }
            calendarPopoverID = ObjectIdentifier(popover)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { notification in
            guard let popover = notification.object as? NSPopover,
                  calendarPopoverID == ObjectIdentifier(popover) else { return }
            calendarPopoverID = nil
            let generation = focusGeneration
            // The presentation binding changes before AppKit has finished retiring
            // the popover's field editor. Moving SwiftUI focus in that transaction
            // can make NSTextView resign against the wrong window and crash.
            // Restore focus only after this specific native popover has closed.
            DispatchQueue.main.async {
                guard generation == focusGeneration, isActiveEditor(), isVisible, !presentation.calendarIsPresented,
                      AppDelegate.shared?.isPopoverShown == true, NSApp.isActive else { return }
                dateButtonFocused = true
            }
        }
        .onDisappear {
            inputOwner.invalidate()
            focusGeneration &+= 1
            isVisible = false
            calendarPopoverID = nil
            dateButtonFocused = false
            presentation.dismissCalendar(ownedBy: calendarOwnerID)
        }
    }
}

/// Identifies the native popover containing this calendar without intercepting
/// AppKit's delegate or borrowing an unrelated popover's lifecycle notifications.
private final class CalendarPopoverOwner {
    weak var view: NSView?
}

private struct CalendarPopoverAnchor: NSViewRepresentable {
    let owner: CalendarPopoverOwner
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setAccessibilityElement(false)
        owner.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

private struct GoalDatePopover: View {
    let value: Date?
    let calendarOwnerID: UUID
    let inputOwner: PolarisFieldEditorOwner
    let isActive: () -> Bool
    let choose: (Date?) -> Void
    @Environment(PolarisPresentation.self) private var presentation
    @Environment(\.polarisPalette) private var palette
    @State private var input = ""
    @State private var month = Date()
    @State private var focusGeneration = 0
    @State private var calendarFocusRequest = 0
    private var parsed: Date? { GoalDateParser.parse(input) }
    private var quickDates: [(String, Date)] {
        let now = Date()
        return [("本周末", GoalPeriod.end(of: .weekOfYear, from: now)),
                ("本月底", GoalPeriod.end(of: .month, from: now)),
                ("下月底", GoalPeriod.end(of: .month, from: Calendar.current.date(byAdding: .month, value: 1, to: now)!)),
                ("今年底", GoalPeriod.end(of: .year, from: now))]
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "calendar").foregroundStyle(palette.muted)
                PolarisSearchField(text: $input, placeholder: "输入日期，如 10月15日", fontSize: 12.5,
                    focusGeneration: focusGeneration, onMove: { _ in focusCalendar() }, onSubmit: submit,
                    onEscape: close, onTab: focusCalendar, shortcutsEnabled: true,
                    editorOwner: inputOwner,
                    isActive: isActive).frame(height: 28)
                Button(action: submit) {
                    Image(systemName: "return").frame(width: 30, height: 32).contentShape(Rectangle())
                }.buttonStyle(GoalControlStyle()).disabled(parsed == nil).accessibilityLabel("使用输入日期")
            }.padding(.horizontal, 14).frame(height: 47)
            palette.line.frame(height: 0.5)
            CalendarPickerView(selectedDate: Binding(get: { value }, set: select), displayedMonth: $month,
                focusRequest: calendarFocusRequest)
                .padding(14)
            HStack(spacing: 5) {
                ForEach(quickDates, id: \.0) { entry in
                    Button { select(entry.1) } label: {
                        Text(entry.0).font(.system(size: 11)).frame(maxWidth: .infinity, minHeight: 32).contentShape(Rectangle())
                    }.buttonStyle(GoalControlStyle())
                }
            }.padding(.horizontal, 12).padding(.bottom, 10)
            if !input.isEmpty {
                Text(parsed.map { "回车确认：\(shortDate($0))" } ?? "未识别日期，请输入如 2027-01-08")
                    .font(.system(size: 10.5)).foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.bottom, 10)
            }
            palette.line.frame(height: 0.5)
            HStack {
                Button("回到本月") { month = Date() }.frame(minHeight: 34).contentShape(Rectangle())
                Spacer()
                Button("清除日期") { select(nil) }.disabled(value == nil).frame(minHeight: 34).contentShape(Rectangle())
            }.buttonStyle(GoalControlStyle()).font(.system(size: 11)).foregroundStyle(palette.secondary).padding(.horizontal, 14)
        }.font(.system(size: 12.5)).foregroundStyle(palette.ink).frame(width: 306).background(palette.raised)
        .onAppear { month = value ?? Date(); focusGeneration += 1; readback() }
        .onChange(of: input) { _, _ in readback() }
        .onReceive(NotificationCenter.default.publisher(for: .polarisCalendarEscape)) { _ in close() }
        .onDisappear { inputOwner.invalidate() }
    }
    private func readback() { DispatchQueue.main.async { AppDelegate.shared?.writeRuntimeState() } }
    private func shortDate(_ date: Date) -> String { date.formatted(.dateTime.year().month().day().locale(DueDateFormatter.locale)) }
    private func submit() { if let parsed { select(parsed) } }
    private func select(_ date: Date?) { inputOwner.performAfterEndingEditing { choose(date) } }
    private func focusCalendar() { inputOwner.performAfterEndingEditing { calendarFocusRequest += 1 } }
    private func close() {
        inputOwner.performAfterEndingEditing { presentation.dismissCalendar(ownedBy: calendarOwnerID) }
    }
}
