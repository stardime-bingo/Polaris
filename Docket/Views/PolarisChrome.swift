import SwiftUI
import AppKit

/// One native material behind the entire panel; content stays on a readable tint.
struct PolarisPanelBackground: View {
    let palette: PolarisPalette
    @AppStorage("polarisGlassEnabled") private var glass = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if glass && !reduceTransparency {
                PolarisVisualEffect(isDark: palette.isDark)
                palette.surface.opacity(palette.isDark ? 0.62 : 0.55)
            } else { palette.surface }
        }.ignoresSafeArea()
    }
}

private struct PolarisVisualEffect: NSViewRepresentable {
    let isDark: Bool
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}

struct PolarisGlassGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26.0, *) { GlassEffectContainer(spacing: 8) { content } }
        else { content }
    }
}

private struct PolarisGlassSurface: ViewModifier {
    var capsule: Bool
    var interactive: Bool
    @AppStorage("polarisGlassEnabled") private var glass = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.polarisPalette) private var palette
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: capsule ? 24 : 10)
        if glass && !reduceTransparency {
            if #available(macOS 26.0, *) {
                content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
            } else { content.background(.regularMaterial, in: shape) }
        } else { content.background(palette.raised, in: shape) }
    }
}

extension View {
    func polarisGlassSurface(capsule: Bool = false, interactive: Bool = true) -> some View {
        modifier(PolarisGlassSurface(capsule: capsule, interactive: interactive))
    }
}

struct PolarisFooter: View {
    var isActive = true
    var onNew: (() -> Void)?
    var onEdit: (() -> Void)?
    var onSettings: (() -> Void)?
    var onActions: (() -> Void)?
    @Environment(\.polarisPalette) private var palette
    @AppStorage("panelShortcutsEnabled") private var localKeys = true
    var body: some View {
        HStack(spacing: 8) {
            Text("Polaris").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.secondary)
            PolarisSyncStatus(visible: isActive)
            Spacer(minLength: 0)
            if let onEdit {
                Button(action: onEdit) {
                    HStack(spacing: 5) { Text("编辑目标"); if localKeys { Text("↵") } }
                        .font(.system(size: 11)).padding(.horizontal, 3).frame(height: 28).contentShape(Rectangle())
                }.buttonStyle(GoalControlStyle()).foregroundStyle(palette.secondary)
            }
            PolarisGlassGroup {
                HStack(spacing: 2) {
                    if let onNew { tool("plus", "新建目标", action: onNew) }
                    if let onActions { tool("ellipsis", "目标操作", action: onActions) }
                    if let onSettings { tool("slider.horizontal.3", "Polaris 设置", action: onSettings) }
                }.polarisGlassSurface()
            }
        }.padding(.horizontal, 16).frame(height: 42)
    }
    private func tool(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12))
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }.buttonStyle(GoalControlStyle()).foregroundStyle(palette.secondary)
            .help(title).accessibilityLabel(title)
    }
}
