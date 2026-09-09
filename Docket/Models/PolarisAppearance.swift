import SwiftUI

// Shared surface and interaction colors. System fonts; no rendering runtime.
enum PolarisSurface: String, CaseIterable, Identifiable {
    case graphite, mist, warm
    var id: String { rawValue }
    var title: String { switch self { case .graphite: "石墨"; case .mist: "雾白"; case .warm: "暖白" } }
}
enum PolarisAccent: String, CaseIterable, Identifiable {
    case klein, lime, violet, coral, rose, cyan
    var id: String { rawValue }
    var title: String { switch self { case .klein: "克莱因蓝"; case .lime: "电光青柠"; case .violet: "电光紫"; case .coral: "珊瑚橙"; case .rose: "玫瑰粉"; case .cyan: "冰川青" } }
    var values: (action: String, text: String, light: String, dark: String, lightSelection: String, darkSelection: String, line: String) {
        switch self {
        case .klein: ("002FA7","FFFFFF","2445A0","A2B7FF","E9EEFC","30394F","668AFF")
        case .lime: ("C6FF4A","25330D","4B6B1E","C6FF4A","EFF5E4","343F2D","AAEE45")
        case .violet: ("7850ED","FFFFFF","6840C5","BEA8FF","F0EBFA","3D354C","A38AFF")
        case .coral: ("FF805F","3B2118","A44328","FFAA91","FAEEE8","473932","FF9474")
        case .rose: ("FF75A2","3E1A29","A83C65","FFA0C0","FAEBF1","46343E","FF91B5")
        case .cyan: ("5BDDF0","143039","216B79","85E5F3","E7F4F6","2D3F45","71DDEC")
        }
    }
}
struct PolarisPalette {
    var surfaceStyle: PolarisSurface = .graphite
    var accentStyle: PolarisAccent = .klein
    var isDark: Bool { surfaceStyle == .graphite }
    var surface: Color { Color(hex: isDark ? "202124" : surfaceStyle == .mist ? "FAFBFC" : "FCFAF6") }
    var raised: Color { Color(hex: isDark ? "292A2D" : surfaceStyle == .mist ? "FFFFFF" : "FFFDFA") }
    var ink: Color { Color(hex: isDark ? "ECEDEF" : surfaceStyle == .mist ? "292C33" : "302D2A") }
    var secondary: Color { Color(hex: isDark ? "B0B3BA" : surfaceStyle == .mist ? "59616C" : "625B51") }
    var muted: Color { Color(hex: isDark ? "A9ADB6" : surfaceStyle == .mist ? "5E6570" : "655E53") }
    var line: Color { Color(hex: isDark ? "37383C" : surfaceStyle == .mist ? "DCDFE4" : "E1DDD6") }
    var hover: Color { Color(hex: isDark ? "2B2C30" : surfaceStyle == .mist ? "F0F1F4" : "F2EFE9") }
    var pressed: Color { Color(hex: isDark ? "3E4045" : surfaceStyle == .mist ? "DFE2E8" : "E0DAD0") }
    var action: Color { Color(hex: accentStyle.values.action) }
    var actionText: Color { Color(hex: accentStyle.values.text) }
    var accentInk: Color { Color(hex: isDark ? accentStyle.values.dark : accentStyle.values.light) }
    var selection: Color { Color(hex: isDark ? "343539" : surfaceStyle == .mist ? "E8EAEE" : "EAE6DF") }
    var selectionLine: Color { Color(hex: isDark ? accentStyle.values.line : accentStyle.values.action) }
}
private struct PolarisPaletteKey: EnvironmentKey { static let defaultValue = PolarisPalette() }
private struct PolarisNowKey: EnvironmentKey { static let defaultValue = Date() }
extension EnvironmentValues {
    var polarisPalette: PolarisPalette { get { self[PolarisPaletteKey.self] } set { self[PolarisPaletteKey.self] = newValue } }
    var polarisNow: Date { get { self[PolarisNowKey.self] } set { self[PolarisNowKey.self] = newValue } }
}
struct PolarisKeycap: View {
    let text: String
    @Environment(\.polarisPalette) private var palette
    var body: some View {
        Text(text).font(.system(size: 10)).foregroundStyle(palette.secondary)
            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
            .background(palette.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(palette.line, lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}
struct PolarisSectionTitle: View {
    let title: String
    @Environment(\.polarisPalette) private var palette
    var body: some View {
        Text(title).font(.system(size: 11, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(palette.secondary)
    }
}
