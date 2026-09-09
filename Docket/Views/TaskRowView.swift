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
    private var featured: Bool { showMenuGoal && Store.shared.menuBarGoal?.id == item.id }
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
                if !item.steps.isEmpty {
                    Text("\(item.steps.filter(\.isCompleted).count) / \(item.steps.count) 子任务")
                        .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(palette.secondary)
                        .contentTransition(.numericText())
                        .accessibilityLabel("子任务已完成 \(item.steps.filter(\.isCompleted).count) 个，共 \(item.steps.count) 个")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Text(item.dueDate.map { DueDateFormatter.format($0, hasTime: item.hasDueTime, now: now) } ?? item.goalPeriod.title)
                    .font(.system(size: 11.5)).monospacedDigit()
            }.foregroundStyle(item.isOverdue(at: now) ? palette.accentInk : palette.secondary)
                .fixedSize().frame(minHeight: 22)
                .help(item.dueDate.map { DueDateFormatter.remaining($0, hasTime: item.hasDueTime, now: now) } ?? "不设截止日期")
          }
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
              }.padding(.leading, 28).padding(.top, 3).padding(.bottom, 2)
                  .transition(.opacity.combined(with: .move(edge: .top)))
          }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .frame(minHeight: 36)
        .background(isSelected ? palette.selection : .clear, in: RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .topLeading) {
            if isSelected { RoundedRectangle(cornerRadius: 1).fill(palette.selectionLine).frame(width: 2, height: 16).padding(.leading, 1).padding(.top, 9) }
        }
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(isSelected && contrast == .increased ? palette.accentInk : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
