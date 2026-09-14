import SwiftUI
import AppKit

struct TaskRowView: View {
    let item: TodoItem
    let onComplete: () -> Void
    var isSelected = false
    var onToggleStep: (UUID) -> Void
    var onSelect: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    @Environment(\.polarisPalette) private var palette
    @Environment(\.polarisNow) private var now
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("showGoalInMenuBar") private var showMenuGoal = true
    @AppStorage("matrixDoFirstLabel") private var doFirstLabel = "优先推进"
    @AppStorage("matrixScheduleLabel") private var scheduleLabel = "持续投入"
    @AppStorage("matrixDelegateLabel") private var delegateLabel = "委派协作"
    @AppStorage("matrixEliminateLabel") private var eliminateLabel = "暂时放下"
    @AppStorage("matrixDoFirstColor") private var doFirstColor = "#EF4444"
    @AppStorage("matrixScheduleColor") private var scheduleColor = "#3B82F6"
    @AppStorage("matrixDelegateColor") private var delegateColor = "#F59E0B"
    @AppStorage("matrixEliminateColor") private var eliminateColor = "#9CA3AF"
    @State private var hovered = false
    private var featured: Bool { showMenuGoal && Store.shared.menuBarGoal?.id == item.id }
    private var countdown: String { DueDateFormatter.countdown(item.dueDate, hasTime: item.hasDueTime, isCompleted: item.isCompleted, now: now) }
    private var deadline: String { item.dueDate.map { DueDateFormatter.absolute($0, hasTime: item.hasDueTime) } ?? countdown }
    private var deadlineColor: String? {
        // Reuse the same calendar-aware state that produces the displayed text.
        switch DueDateFormatter.countdownState(item.dueDate, hasTime: item.hasDueTime, isCompleted: item.isCompleted, now: now) {
        case .overdueDays, .overdueHours, .overdueLessThanHour: "C95151"
        case .dueNow, .remainingHours, .remainingLessThanHour: "B57826"
        default: nil
        }
    }
    private func quadrantColor(_ quadrant: Quadrant) -> String {
        switch quadrant {
        case .doFirst: doFirstColor
        case .schedule: scheduleColor
        case .delegate: delegateColor
        case .eliminate: eliminateColor
        }
    }
    private func quadrantLabel(_ quadrant: Quadrant) -> String {
        switch quadrant {
        case .doFirst: doFirstLabel
        case .schedule: scheduleLabel
        case .delegate: delegateLabel
        case .eliminate: eliminateLabel
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          summaryControl
              .onHover { value in
                  hovered = value
                  AppDelegate.shared?.recordVerificationEvent("list.row.hover", fields: ["goalID": item.id.uuidString, "hovered": value, "selected": isSelected])
                  AppDelegate.shared?.writeRuntimeState()
              }
          if !item.steps.isEmpty {
              VStack(alignment: .leading, spacing: 0) {
                  ForEach(item.steps) { step in
                      Button { onToggleStep(step.id) } label: {
                          HStack(alignment: .top, spacing: 8) {
                              Image(systemName: step.isCompleted ? "checkmark.circle" : "circle")
                                  .font(.system(size: 13)).frame(width: 16, height: 20)
                                  .foregroundStyle(step.isCompleted ? palette.accentInk : palette.muted)
                              Text(step.title).font(PolarisType.detail)
                                  .foregroundStyle(step.isCompleted ? palette.completedText : palette.ink)
                                  .strikethrough(step.isCompleted, color: palette.completedText.opacity(0.4))
                                  .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                                  .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
                          }.padding(.horizontal, 6).padding(.vertical, 5).frame(minHeight: 30).contentShape(Rectangle())
                      }.buttonStyle(GoalControlStyle())
                          .accessibilityLabel("\(step.isCompleted ? "取消完成" : "完成")子任务：\(step.title)")
                          .accessibilityValue(step.isCompleted ? "已完成" : "未完成")
                  }
              }.padding(.leading, 36).padding(.trailing, 8).padding(.bottom, 7)
                  .transition(.opacity.combined(with: .move(edge: .top)))
          }
        }
        .frame(minHeight: 36)
        .overlay(alignment: .topLeading) {
            if isSelected { RoundedRectangle(cornerRadius: 1).fill(palette.selectionLine).frame(width: 2, height: 16).padding(.leading, 1).padding(.top, 9) }
        }
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(isSelected && contrast == .increased ? palette.accentInk : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var summaryControl: some View {
        if let onSelect {
            Button {
                onSelect()
                // Use the system double-click count instead of competing tap
                // recognizers. Keyboard/accessibility activation remains select.
                if let event = NSApp.currentEvent,
                   event.type == .leftMouseUp || event.type == .leftMouseDown,
                   event.clickCount == 2 {
                    onEdit?()
                }
            } label: { summary }
                .buttonStyle(TaskRowSummaryStyle(isSelected: isSelected, hovered: hovered))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            // Legacy swipe wrappers own their own tap gesture.
            summary.background(isSelected ? palette.goalSelection : hovered ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
    }

    private var summary: some View {
          HStack(alignment: .top, spacing: 8) {
            Group {
                if featured { Image(nsImage: PolarisSymbol.menuImage()).renderingMode(.template).resizable().scaledToFit().frame(width: 24, height: 18) }
                else { Circle().strokeBorder(isSelected ? palette.accentInk : palette.muted, lineWidth: 1).frame(width: 10, height: 10) }
            }.frame(width: 24, height: 20).foregroundStyle(featured ? palette.accentInk : palette.muted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(PolarisType.title)
                    .foregroundStyle(palette.ink).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if let quadrant = item.quadrant {
                        HStack(spacing: 4) {
                            Image(systemName: quadrant.icon).font(.system(size: 11))
                                .foregroundStyle(palette.readableColor(hex: quadrantColor(quadrant), minimum: 3))
                                .frame(width: 12, height: 17).accessibilityHidden(true)
                            Text(quadrantLabel(quadrant)).lineLimit(1)
                        }.foregroundStyle(palette.secondary)
                            .help(quadrantLabel(quadrant))
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(L10n.matrix)：\(quadrantLabel(quadrant))")
                    }
                    Spacer(minLength: 0)
                    Text(countdown).monospacedDigit().fixedSize()
                        .foregroundStyle(deadlineColor.map { palette.readableColor(hex: $0) } ?? palette.secondary)
                        .help(deadline)
                        .accessibilityLabel(item.dueDate == nil ? countdown : "\(countdown)，\(deadline)")
                }.font(PolarisType.metadata).frame(minHeight: 17)
                if !item.steps.isEmpty {
                    HStack(spacing: 6) {
                        let completed = item.steps.filter(\.isCompleted).count
                        Capsule().fill(palette.accentInk.opacity(0.12))
                            .overlay(alignment: .leading) {
                                Capsule().fill(palette.accentInk)
                                    .frame(width: 36 * CGFloat(completed) / CGFloat(item.steps.count))
                            }.frame(width: 36, height: 3).accessibilityHidden(true)
                        Text("\(completed) / \(item.steps.count) 子任务")
                    }
                        .font(PolarisType.metadata).monospacedDigit().foregroundStyle(palette.secondary)
                        .contentTransition(.numericText())
                        .accessibilityLabel("子任务已完成 \(item.steps.filter(\.isCompleted).count) 个，共 \(item.steps.count) 个")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding(.horizontal, 8).padding(.vertical, 7).contentShape(Rectangle())
    }

}


private struct TaskRowSummaryStyle: ButtonStyle {
    let isSelected: Bool
    let hovered: Bool
    @Environment(\.polarisPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? palette.goalPressed : isSelected ? palette.goalSelection : hovered ? palette.hover : .clear,
                        in: RoundedRectangle(cornerRadius: 5))
    }
}
