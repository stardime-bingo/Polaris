import SwiftUI
import Carbon.HIToolbox

struct PolarisSettingsView: View {
    @Binding var path: [NavDestination]
    @Environment(\.polarisPalette) private var palette
    @AppStorage("polarisSurface") private var surface = "graphite"
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
                    PolarisAccentSettings().padding(.bottom, 8)
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

/// The color well uses the native macOS panel (including its system eyedropper).
/// HEX edits stay local while incomplete; a complete RRGGBB previews immediately.
private struct PolarisAccentSettings: View {
    @AppStorage("polarisAccent") private var accent = PolarisAccent.klein.rawValue
    @AppStorage("polarisCustomAccentHex") private var customHex = PolarisAppearancePreferences.defaultHex
    @Environment(\.polarisPalette) private var palette
    @State private var hexDraft = ""
    @State private var invalidHex = false
    @FocusState private var hexFocused: Bool

    private var currentHex: String {
        if accent == PolarisAppearancePreferences.customAccent, let rgb = PolarisRGB(hex: customHex) { return rgb.hex }
        return (PolarisAccent(rawValue: accent) ?? .klein).hex
    }
    private var customColor: Binding<Color> {
        Binding(get: { Color(hex: currentHex) }, set: { color in
            guard let hex = color.toHex() else { return }
            applyCustom(hex)
            if let rgb = PolarisRGB(hex: hex) { hexDraft = "#" + rgb.hex }
        })
    }

    private var hexInput: Binding<String> {
        Binding(get: { hexDraft }, set: { value in
            hexDraft = value
            invalidHex = false
            let digits = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if digits.count == (digits.hasPrefix("#") ? 7 : 6), let rgb = PolarisRGB(hex: digits) {
                applyCustom(rgb.hex)
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ForEach(PolarisAccent.allCases) { color in
                    Button {
                        accent = color.rawValue
                        invalidHex = false
                        hexDraft = "#" + color.hex
                    } label: {
                        Circle().fill(Color(hex: color.hex)).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(palette.ink.opacity(0.2), lineWidth: 0.5))
                            .frame(width: 32, height: 32).contentShape(Rectangle())
                            .overlay(Circle().strokeBorder(accent == color.rawValue ? palette.ink : .clear, lineWidth: 1).frame(width: 22, height: 22))
                    }.buttonStyle(GoalControlStyle())
                        .help(color.title).accessibilityLabel(color.title)
                        .accessibilityAddTraits(accent == color.rawValue ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Text(L10n.appearanceAccentCustom).foregroundStyle(palette.secondary)
                ColorPicker(L10n.appearanceAccentCustom, selection: customColor, supportsOpacity: false)
                    .labelsHidden().controlSize(.small)
                    .accessibilityAddTraits(accent == PolarisAppearancePreferences.customAccent ? .isSelected : [])
                Spacer(minLength: 4)
                TextField("#RRGGBB", text: hexInput)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textFieldStyle(.roundedBorder).frame(width: 92)
                    .focused($hexFocused).accessibilityLabel(L10n.appearanceAccentHex)
                    .onSubmit { commitHex() }
            }.frame(minHeight: 30)
            HStack {
                if invalidHex {
                    Text(L10n.appearanceAccentInvalid)
                        .font(.system(size: 10.5)).foregroundStyle(palette.accentInk)
                }
                Spacer(minLength: 0)
                Button(L10n.appearanceAccentReset) {
                    PolarisAppearancePreferences.restoreDefaultAccent(in: .standard)
                    invalidHex = false
                    hexDraft = "#" + PolarisAppearancePreferences.defaultHex
                }.buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(palette.accentInk)
                    .disabled(accent == PolarisAccent.klein.rawValue)
            }
            if accent == PolarisAppearancePreferences.customAccent {
                Text(L10n.appearanceAccentContrast)
                    .font(.system(size: 10.5)).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { hexDraft = "#" + currentHex }
        .onChange(of: currentHex) { _, value in
            if !hexFocused { hexDraft = "#" + value }
        }
        .onChange(of: hexFocused) { _, focused in if !focused { commitHex() } }
    }

    private func commitHex() {
        guard let rgb = PolarisRGB(hex: hexDraft) else { invalidHex = true; return }
        invalidHex = false
        if rgb.hex != currentHex { applyCustom(rgb.hex) }
        hexDraft = "#" + rgb.hex
    }

    private func applyCustom(_ hex: String) {
        guard let rgb = PolarisRGB(hex: hex) else { return }
        invalidHex = false
        // Native controls can echo a programmatic preset/reset update. An
        // unchanged color must not change the user's selected accent mode.
        guard rgb.hex != currentHex else { return }
        PolarisAppearancePreferences.setCustom(rgb.hex, in: .standard)
    }
}
