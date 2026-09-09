import SwiftUI
import Carbon.HIToolbox

struct PolarisSettingsView: View {
    @Binding var path: [NavDestination]
    @Environment(\.polarisPalette) private var palette
    @AppStorage("polarisSurface") private var surface = "graphite"
    @AppStorage("polarisAccent") private var accent = "klein"
    @AppStorage("panelShortcutsEnabled") private var localKeys = true
    @AppStorage("polarisGlassEnabled") private var glass = true
    @AppStorage("polarisMotionEnabled") private var motion = true
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { path.removeLast() } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32).contentShape(Rectangle()) }.buttonStyle(GoalControlStyle()).accessibilityLabel("返回")
                Spacer(); Text("设置").font(.system(size: 12.5, weight: .medium)); Spacer(); Color.clear.frame(width: 32)
            }.padding(.horizontal, 13).frame(height: 48)
            palette.line.frame(height: 0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PolarisSectionTitle(title: "外观").padding(.bottom, 8)
                    HStack(spacing: 12) {
                        ForEach(PolarisAccent.allCases) { color in
                            Button { accent = color.rawValue } label: {
                                Circle().fill(Color(hex: color.values.action)).frame(width: 12, height: 12)
                                    .overlay(Circle().strokeBorder(palette.ink.opacity(0.15), lineWidth: 0.5))
                                    .frame(width: 32, height: 32).contentShape(Rectangle())
                                    .overlay(Circle().strokeBorder(accent == color.rawValue ? palette.ink : .clear, lineWidth: 1).frame(width: 22, height: 22))
                            }.buttonStyle(GoalControlStyle()).help(color.title).accessibilityLabel(color.title).accessibilityAddTraits(accent == color.rawValue ? .isSelected : [])
                        }
                    }.padding(.bottom, 8)
                    HStack(spacing: 12) {
                        Text("底色").foregroundStyle(palette.secondary)
                        Spacer()
                        Picker("底色", selection: $surface) { ForEach(PolarisSurface.allCases) { Text($0.title).tag($0.rawValue) } }
                            .labelsHidden().pickerStyle(.segmented).controlSize(.small).frame(width: 200)
                    }.frame(minHeight: 36)
                    Toggle("玻璃质感", isOn: $glass).toggleStyle(.switch).controlSize(.small).tint(palette.action).frame(height: 36)
                    palette.line.frame(height: 0.5).padding(.vertical, 16)
                    PolarisSectionTitle(title: "交互").padding(.bottom, 8)
                    Toggle("轻动效", isOn: $motion).toggleStyle(.switch).controlSize(.small).tint(palette.action).frame(height: 36)
                    ShortcutRecorderView().padding(.vertical, 8)
                    Toggle(isOn: $localKeys) { HStack { Text("面板内快捷键"); Spacer() } }.toggleStyle(.switch).controlSize(.small).tint(palette.action).frame(height: 36)
                    Text(localKeys ? "↑ ↓ 选择　↵ 编辑　⌘N 新建　⌘K 操作" : "已隐藏操作提示；Esc 仍可返回或收起")
                        .font(.system(size: 11)).foregroundStyle(palette.secondary).padding(.bottom, 16)
                    palette.line.frame(height: 0.5)
                    navigation("目标矩阵", "square.grid.2x2", .matrix)
                    navigation("已达成目标", "checkmark.circle", .completed)
                    navigation("更多设置", "slider.horizontal.3", .advancedSettings)
                    Text("Polaris · \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")").font(.system(size: 10)).foregroundStyle(palette.muted).padding(.top, 10)
                }.font(.system(size: 12.5)).padding(20)
            }.scrollIndicators(.automatic)
        }
        .toolbar(.hidden, for: .windowToolbar)
    }
    private func navigation(_ title: String, _ icon: String, _ destination: NavDestination) -> some View {
        Button { path.append(destination) } label: { HStack(spacing: 8) { Image(systemName: icon).font(.system(size: 14)).foregroundStyle(palette.secondary).frame(width: 18); Text(title); Spacer(); Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(palette.muted) }.frame(height: 36).contentShape(Rectangle()) }.buttonStyle(GoalControlStyle())
    }
}
