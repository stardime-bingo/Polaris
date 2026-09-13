import SwiftUI

struct TaskRowView: View {
    let item: TodoItem
    let onComplete: () -> Void
    var isSelected = false
    var onToggleStep: (UUID) -> Void
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
    @GestureState private var pressed = false
    private var featured: Bool { showMenuGoal && Store.shared.menuBarGoal?.id == item.id }
    private var countdown: String { DueDateFormatter.countdown(item.dueDate, hasTime: item.hasDueTime, isCompleted: item.isCompleted, now: now) }
    private var deadline: String { item.dueDate.map { DueDateFormatter.absolute($0, hasTime: item.hasDueTime) } ?? countdown }
    private func quadrantLabel(_ quadrant: Quadrant) -> String {
        switch quadrant {
        case .doFirst: doFirstLabel
        case .schedule: scheduleLabel
        case .delegate: delegateLabel
        case .eliminate: eliminateLabel
        }
    }
    private func quadrantColor(_ quadrant: Quadrant) -> Color {
        let hex: String
        switch quadrant {
        case .doFirst: hex = doFirstColor
        case .schedule: hex = scheduleColor
        case .delegate: hex = delegateColor
        case .eliminate: hex = eliminateColor
        }
        return palette.readableColor(hex: hex, minimum: 3)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          HStack(alignment: .top, spacing: 8) {
            Group {
                if featured { Image(nsImage: PolarisSymbol.menuImage()).renderingMode(.template).resizable().scaledToFit().frame(width: 24, height: 18) }
                else { Circle().strokeBorder(isSelected ? palette.accentInk : palette.muted, lineWidth: 1).frame(width: 10, height: 10) }
            }.frame(width: 24, height: 20).foregroundStyle(featured ? (palette.isDark ? Color.white : Color.black) : palette.muted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 14, weight: featured ? .medium : .regular))
                    .foregroundStyle(palette.ink).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if let quadrant = item.quadrant {
                        HStack(spacing: 4) {
                            Image(systemName: quadrant.icon).foregroundStyle(quadrantColor(quadrant))
                            Text(quadrantLabel(quadrant)).lineLimit(1)
                        }.foregroundStyle(palette.secondary)
                            .help(quadrantLabel(quadrant))
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(L10n.matrix)：\(quadrantLabel(quadrant))")
                    }
                    Spacer(minLength: 0)
                    Text(countdown).monospacedDigit().fixedSize()
                        .foregroundStyle(item.isOverdue(at: now) ? palette.accentInk : palette.secondary)
                        .help(deadline)
                        .accessibilityLabel("\(countdown)，\(deadline)")
                }.font(.system(size: 11)).frame(minHeight: 18)
                if !item.steps.isEmpty {
                    Text("\(item.steps.filter(\.isCompleted).count) / \(item.steps.count) 子任务")
                        .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(palette.secondary)
                        .contentTransition(.numericText())
                        .accessibilityLabel("子任务已完成 \(item.steps.filter(\.isCompleted).count) 个，共 \(item.steps.count) 个")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding(.horizontal, 8).padding(.vertical, 7)
          .background(pressed ? palette.pressed : isSelected ? palette.selection : hovered ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 5))
          if !item.steps.isEmpty {
              VStack(alignment: .leading, spacing: 0) {
                  ForEach(item.steps) { step in
                      Button { onToggleStep(step.id) } label: {
                          HStack(alignment: .top, spacing: 8) {
                              Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                                  .font(.system(size: 13)).frame(width: 16, height: 20)
                                  .foregroundStyle(step.isCompleted ? palette.accentInk : palette.muted)
                              Text(step.title).font(.system(size: 12.5))
                                  .foregroundStyle(step.isCompleted ? palette.secondary : palette.ink)
                                  .strikethrough(step.isCompleted, color: palette.muted.opacity(0.6))
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
        .onHover { value in
            hovered = value
            AppDelegate.shared?.recordVerificationEvent("list.row.hover", fields: ["goalID": item.id.uuidString, "hovered": value, "selected": isSelected])
            AppDelegate.shared?.writeRuntimeState()
        }
        .simultaneousGesture(LongPressGesture(minimumDuration: .infinity, maximumDistance: 4)
            .updating($pressed) { value, state, _ in state = value })
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
