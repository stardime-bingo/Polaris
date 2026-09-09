import SwiftUI

struct GoalChecklistView: View {
    @Binding var steps: [GoalStep]
    @Binding var entry: String
    var syncEnabled = false
    @FocusState private var adding: Bool
    @Environment(\.polarisPalette) private var palette
    private var cleanEntry: String { entry.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("子任务").font(.system(size: 11, weight: .medium))
                Spacer()
                if !steps.isEmpty {
                    Text("\(steps.filter(\.isCompleted).count) / \(steps.count)")
                        .font(.system(size: 11)).monospacedDigit().accessibilityLabel("已完成 \(steps.filter(\.isCompleted).count) 个，共 \(steps.count) 个子任务")
                }
            }.foregroundStyle(palette.secondary)
            VStack(spacing: 0) {
                ForEach($steps) { $step in
                    GoalChecklistRow(step: $step) {
                        let id = step.id
                        steps.removeAll { $0.id == id }
                    }
                }
                if !steps.isEmpty { palette.line.frame(height: 0.5).padding(.leading, 34).padding(.vertical, 3) }
                HStack(spacing: 2) {
                    Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(palette.muted).frame(width: 32)
                    TextField("添加子任务…", text: $entry).textFieldStyle(.plain)
                        .font(.system(size: 12.5)).focused($adding).onSubmit(add)
                        .accessibilityLabel("添加子任务")
                    Button(action: add) {
                        Image(systemName: "return").font(.system(size: 12))
                            .frame(width: 32, height: 36).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(palette.accentInk)
                        .disabled(cleanEntry.isEmpty).opacity(cleanEntry.isEmpty ? 0.35 : 1)
                        .help("添加，或按回车继续").accessibilityLabel("添加这条子任务")
                }.frame(minHeight: 38).contentShape(Rectangle())
            }
            if syncEnabled {
                Text("子任务保存在 Polaris；目标标题和描述可同步至 Apple 提醒事项。")
                    .font(.system(size: 10.5)).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func add() {
        guard !cleanEntry.isEmpty else { return }
        steps.append(GoalStep(title: cleanEntry))
        entry = ""
        adding = true
    }
}

private struct GoalChecklistRow: View {
    @Binding var step: GoalStep
    let remove: () -> Void
    @Environment(\.polarisPalette) private var palette
    @State private var hovered = false
    @FocusState private var focusedControl: Control?
    private enum Control: Hashable { case toggle, title, remove }

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            Button { step.isCompleted.toggle() } label: {
                Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14)).foregroundStyle(step.isCompleted ? palette.secondary : palette.muted)
                    .frame(width: 32, height: 34).contentShape(Rectangle())
            }.buttonStyle(.plain).focused($focusedControl, equals: .toggle)
                .accessibilityLabel(step.isCompleted ? "取消完成子任务：\(step.title)" : "完成子任务：\(step.title)")
                .accessibilityValue(step.isCompleted ? "已完成" : "未完成")
            TextField("子任务内容", text: $step.title, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 12.5)).lineLimit(1...4)
                .foregroundStyle(step.isCompleted ? palette.secondary : palette.ink)
                .strikethrough(step.isCompleted, color: palette.muted.opacity(0.55))
                .padding(.vertical, 9).focused($focusedControl, equals: .title)
                .accessibilityLabel("子任务内容")
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(palette.secondary)
                    .frame(width: 32, height: 34).contentShape(Rectangle())
            }.buttonStyle(.plain).focused($focusedControl, equals: .remove)
                .opacity(hovered || focusedControl != nil ? 1 : 0.3)
                .help("删除子任务").accessibilityLabel("删除子任务：\(step.title)")
        }
        .background(hovered || focusedControl != nil ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle()).onHover { hovered = $0 }
    }
}
