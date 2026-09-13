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
                Spacer(); Text("设置").font(.system(size: 13, weight: .semibold)); Spacer(); Color.clear.frame(width: 32)
            }.padding(.horizontal, 13).frame(height: 48)
            palette.line.frame(height: 0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("外观").font(.system(size: 13, weight: .semibold)).padding(.bottom, 8)
                    PolarisAccentSettings().padding(.bottom, 8)
                    HStack(spacing: 12) {
                        Text("底色").foregroundStyle(palette.secondary)
                        Spacer()
                        HStack(spacing: 2) {
                            ForEach(PolarisSurface.allCases) { option in
                                Button { surface = option.rawValue } label: {
                                    Text(option.title).font(.system(size: 13))
                                        .foregroundStyle(palette.ink)
                                        .frame(maxWidth: .infinity).frame(height: 26)
                                        .background(surface == option.rawValue ? palette.raised : .clear, in: RoundedRectangle(cornerRadius: 5))
                                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(surface == option.rawValue ? palette.line : .clear, lineWidth: 0.5))
                                        .contentShape(Rectangle())
                                }.buttonStyle(GoalControlStyle())
                                    .accessibilityLabel("底色，" + option.title)
                                    .accessibilityAddTraits(surface == option.rawValue ? .isSelected : [])
                            }
                        }.padding(2).frame(width: 204)
                            .background(palette.hover, in: RoundedRectangle(cornerRadius: 7))
                    }.frame(minHeight: 36)
                    Toggle(isOn: $glass) { HStack { Text("玻璃质感"); Spacer() } }.toggleStyle(.switch).controlSize(.small).tint(palette.action).frame(height: 36)
                    palette.line.frame(height: 0.5).padding(.vertical, 16)
                    Text("交互").font(.system(size: 13, weight: .semibold)).padding(.bottom, 8)
                    Toggle(isOn: $motion) { HStack { Text("轻动效"); Spacer() } }.toggleStyle(.switch).controlSize(.small).tint(palette.action).frame(height: 36)
                    ShortcutRecorderView().padding(.vertical, 8)
                    Toggle(isOn: $localKeys) { HStack { Text("面板内快捷键"); Spacer() } }.toggleStyle(.switch).controlSize(.small).tint(palette.action).frame(height: 36)
                    Text(localKeys ? "↑ ↓ 选择　↵ 编辑　⌘N 新建　⌘K 操作" : "已隐藏操作提示；Esc 仍可返回或收起")
                        .font(.system(size: 11)).foregroundStyle(palette.secondary).padding(.bottom, 16)
                    palette.line.frame(height: 0.5)
                    navigation("目标矩阵", "square.grid.2x2", .matrix)
                    navigation("已达成目标", "checkmark.circle", .completed)
                    navigation("更多设置", "slider.horizontal.3", .advancedSettings)
                    Text("Polaris · \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")").font(.system(size: 11)).foregroundStyle(palette.muted).padding(.top, 10)
                }.font(.system(size: 13)).padding(20)
            }.scrollIndicators(.automatic)
        }
        .toolbar(.hidden, for: .windowToolbar)
    }
    private func navigation(_ title: String, _ icon: String, _ destination: NavDestination) -> some View {
        Button { path.append(destination) } label: { HStack(spacing: 8) { Image(systemName: icon).font(.system(size: 14)).foregroundStyle(palette.secondary).frame(width: 18); Text(title); Spacer(); Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(palette.muted) }.frame(height: 36).contentShape(Rectangle()) }.buttonStyle(GoalControlStyle())
    }
}

/// The entire row anchors an in-app picker so selecting colors never transfers
/// focus to a detached NSColorPanel or restores its stale screen position.
private struct PolarisAccentSettings: View {
    @AppStorage("polarisAccent") private var accent = PolarisAccent.klein.rawValue
    @AppStorage("polarisCustomAccentHex") private var customHex = PolarisAppearancePreferences.defaultHex
    @Environment(\.polarisPalette) private var palette
    @State private var pickerPresented = false

    private var currentHex: String {
        if accent == PolarisAppearancePreferences.customAccent, let rgb = PolarisRGB(hex: customHex) { return rgb.hex }
        return (PolarisAccent(rawValue: accent) ?? .klein).hex
    }
    private var selectedHex: Binding<String> {
        Binding(get: { currentHex }, set: { hex in
            guard let rgb = PolarisRGB(hex: hex), rgb.hex != currentHex else { return }
            PolarisAppearancePreferences.setCustom(rgb.hex, in: .standard)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ForEach(PolarisAccent.allCases) { color in
                    Button { accent = color.rawValue } label: {
                        Circle().fill(Color(hex: color.hex)).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(palette.ink.opacity(0.2), lineWidth: 0.5))
                            .frame(width: 32, height: 32).contentShape(Rectangle())
                            .overlay(Circle().strokeBorder(accent == color.rawValue ? palette.ink : .clear, lineWidth: 1).frame(width: 22, height: 22))
                    }.buttonStyle(GoalControlStyle())
                        .help(color.title).accessibilityLabel(color.title)
                        .accessibilityAddTraits(accent == color.rawValue ? .isSelected : [])
                }
                Spacer(minLength: 4)
                Button("恢复默认") { PolarisAppearancePreferences.restoreDefaultAccent(in: .standard) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(palette.secondary)
                    .disabled(accent == PolarisAccent.klein.rawValue)
                    .accessibilityLabel(L10n.appearanceAccentReset)
            }
            Button { pickerPresented.toggle() } label: {
                HStack(spacing: 8) {
                    Text(L10n.appearanceAccentCustom).foregroundStyle(palette.ink)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4).fill(Color(hex: currentHex)).frame(width: 24, height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(palette.ink.opacity(0.15), lineWidth: 0.5))
                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(palette.muted)
                }.frame(height: 36).contentShape(Rectangle())
            }.buttonStyle(GoalControlStyle())
                .accessibilityLabel(L10n.appearanceAccentCustom)
                .popover(isPresented: $pickerPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                    PolarisColorPicker(hex: selectedHex, onDone: { pickerPresented = false })
                        .environment(\.polarisPalette, palette)
                        .environment(\.colorScheme, palette.isDark ? .dark : .light)
                }
                .polarisPickerEscape(isPresented: $pickerPresented)
        }
    }
}

private struct PolarisColorPicker: View {
    @Binding var hex: String
    let onDone: () -> Void
    @Environment(\.polarisPalette) private var palette
    @State private var hue: Double
    @State private var saturation: Double
    @State private var brightness: Double
    @State private var precise = false
    @State private var hexDraft: String
    @State private var invalidHex = false
    @FocusState private var hexFocused: Bool

    init(hex: Binding<String>, onDone: @escaping () -> Void) {
        _hex = hex
        self.onDone = onDone
        let color = PolarisRGB(hex: hex.wrappedValue) ?? .black
        let hsb = color.hsb
        _hue = State(initialValue: hsb.hue)
        _saturation = State(initialValue: hsb.saturation)
        _brightness = State(initialValue: hsb.brightness)
        _hexDraft = State(initialValue: "#" + color.hex)
    }

    private var color: PolarisRGB { PolarisRGB(hue: hue, saturation: saturation, brightness: brightness) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(color.color).frame(width: 20, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(palette.line, lineWidth: 0.5))
                Text(L10n.appearanceAccentCustom).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("完成", action: onDone).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(palette.secondary)
            }
            colorField
            VStack(spacing: 4) {
                LinearGradient(colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) }, startPoint: .leading, endPoint: .trailing)
                    .frame(height: 5).clipShape(Capsule()).accessibilityHidden(true)
                channel("色相", value: $hue)
            }
            DisclosureGroup("精确颜色", isExpanded: $precise) {
                VStack(spacing: 8) {
                    channel("饱和度", value: $saturation)
                    channel("亮度", value: $brightness)
                    HStack {
                        Text("HEX").font(.system(size: 11)).foregroundStyle(palette.secondary)
                        Spacer()
                        TextField("#RRGGBB", text: Binding(get: { hexDraft }, set: { value in
                            hexDraft = value
                            invalidHex = false
                            let digits = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            if digits.count == (digits.hasPrefix("#") ? 7 : 6) { applyHex(value) }
                        })).textFieldStyle(.roundedBorder).frame(width: 108)
                            .font(.system(size: 11, design: .monospaced))
                            .focused($hexFocused).accessibilityLabel(L10n.appearanceAccentHex)
                            .onSubmit { applyHex(hexDraft, normalize: true) }
                    }
                    if invalidHex { Text(L10n.appearanceAccentInvalid).font(.system(size: 11)).foregroundStyle(palette.secondary) }
                }.padding(.top, 8)
            }.font(.system(size: 11)).tint(palette.secondary)
        }
        .padding(14).frame(width: 276)
        .foregroundStyle(palette.ink)
        .background(palette.raised)
        .onAppear {
            if let rgb = PolarisRGB(hex: hex) { receive(rgb); hexDraft = "#" + rgb.hex }
        }
        .onChange(of: hex) { _, value in
            if let rgb = PolarisRGB(hex: value), rgb.hex != color.hex { receive(rgb) }
            if !hexFocused { hexDraft = "#" + value }
        }
        .onChange(of: hexFocused) { _, focused in if !focused { applyHex(hexDraft, normalize: true) } }
    }

    private var colorField: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ZStack {
                    LinearGradient(colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                }.clipShape(RoundedRectangle(cornerRadius: 6))
                Circle().strokeBorder(.black.opacity(0.55), lineWidth: 3)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    .frame(width: 12, height: 12)
                    .position(x: saturation * geometry.size.width, y: (1 - brightness) * geometry.size.height)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                saturation = Double(max(0, min(1, value.location.x / geometry.size.width)))
                brightness = Double(1 - max(0, min(1, value.location.y / geometry.size.height)))
                publish()
            })
            .accessibilityLabel("选色区域：横向调整饱和度，纵向调整亮度")
            .accessibilityHint("也可以展开精确颜色使用滑块调整")
        }.frame(height: 144)
    }

    private func channel(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(palette.secondary).frame(width: 38, alignment: .leading)
            Slider(value: Binding(get: { value.wrappedValue }, set: { newValue in
                value.wrappedValue = newValue
                publish()
            }), in: 0...1).controlSize(.small).tint(palette.secondary).accessibilityLabel(title)
        }
    }

    private func publish() {
        hex = color.hex
        hexDraft = "#" + color.hex
        invalidHex = false
    }

    private func receive(_ rgb: PolarisRGB) {
        let hsb = rgb.hsb
        // Gray/black have no hue. Retain the user's last hue while moving
        // through those edges so the color field doesn't jump back to red.
        if hsb.saturation > 0 { hue = hsb.hue }
        saturation = hsb.saturation
        brightness = hsb.brightness
    }

    private func applyHex(_ value: String, normalize: Bool = false) {
        guard let rgb = PolarisRGB(hex: value) else { invalidHex = true; return }
        receive(rgb)
        hex = rgb.hex
        if normalize { hexDraft = "#" + rgb.hex }
        invalidHex = false
    }
}
