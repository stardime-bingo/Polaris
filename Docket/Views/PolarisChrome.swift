import SwiftUI
import AppKit

/// Text stays on a clean, opaque surface. Glass belongs to the small controls,
/// not the reading canvas, where the desktop would tint every row.
struct PolarisPanelBackground: View {
    let palette: PolarisPalette
    var body: some View {
        palette.surface.ignoresSafeArea()
    }
}

/// SF system text, with the platform's Chinese fallback and optical sizing.
/// Only navigation uses a stronger weight; content and metadata stay regular.
enum PolarisType {
    static let navigation = Font.system(size: 13, weight: .semibold)
    static let title = Font.system(size: 13, weight: .regular)
    static let detail = Font.system(size: 12, weight: .regular)
    static let metadata = Font.system(size: 11, weight: .regular)
    static let editorTitle = Font.system(size: 16, weight: .regular)
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
            Text("Polaris").font(PolarisType.metadata).foregroundStyle(palette.secondary)
            PolarisSyncStatus(visible: isActive)
            Spacer(minLength: 0)
            if let onEdit {
                Button(action: onEdit) {
                    HStack(spacing: 5) { Text("编辑目标"); if localKeys { Text("↵") } }
                        .font(PolarisType.metadata).padding(.horizontal, 3).frame(height: 28).contentShape(Rectangle())
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
