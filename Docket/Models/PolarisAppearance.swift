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
    var hex: String {
        switch self {
        case .klein: "002FA7"
        case .lime: "C6FF4A"
        case .violet: "7850ED"
        case .coral: "FF805F"
        case .rose: "FF75A2"
        case .cyan: "5BDDF0"
        }
    }
}

/// Opaque sRGB used by persistence and contrast checks; no view or screen state.
struct PolarisRGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    static let black = PolarisRGB(red: 0, green: 0, blue: 0)
    static let white = PolarisRGB(red: 1, green: 1, blue: 1)

    init(red: Double, green: Double, blue: Double) {
        self.red = max(0, min(1, red))
        self.green = max(0, min(1, green))
        self.blue = max(0, min(1, blue))
    }

    /// Accept RGB or RRGGBB with one optional #; reject alpha and partial input.
    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard [3, 6].contains(digits.count),
              digits.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) else { return nil }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255)
    }

    var hex: String {
        String(format: "%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
    var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    func contrast(with other: PolarisRGB) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }
    var readableLabel: PolarisRGB { contrast(with: .white) >= contrast(with: .black) ? .white : .black }

    func mixed(with other: PolarisRGB, amount: Double) -> PolarisRGB {
        let t = max(0, min(1, amount))
        return PolarisRGB(red: red + (other.red - red) * t,
                          green: green + (other.green - green) * t,
                          blue: blue + (other.blue - blue) * t)
    }

    /// Keep the exact color if readable. Otherwise use the smallest mix toward
    /// white/black that reaches the target on every supplied surface. This changes
    /// lightness, not the stored color or its RGB hue; all accent text shares it.
    func readable(on backgrounds: [PolarisRGB], minimum: Double = 4.5) -> PolarisRGB {
        guard !backgrounds.isEmpty else { return self }
        func contrastFloor(_ value: PolarisRGB) -> Double { backgrounds.map { value.contrast(with: $0) }.min()! }
        guard contrastFloor(self) < minimum else { return self }
        let endpoint: PolarisRGB = contrastFloor(.white) >= contrastFloor(.black) ? .white : .black
        guard contrastFloor(endpoint) >= minimum else { return endpoint }
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<32 {
            let middle = (lower + upper) / 2
            if contrastFloor(mixed(with: endpoint, amount: middle)) >= minimum { upper = middle }
            else { lower = middle }
        }
        return mixed(with: endpoint, amount: upper)
    }
}

struct PolarisPalette {
    var surfaceStyle: PolarisSurface = .graphite
    var accentStyle: PolarisAccent = .klein
    var customAccentHex: String? = nil
    var isDark: Bool { surfaceStyle == .graphite }
    var surfaceRGB: PolarisRGB { PolarisRGB(hex: isDark ? "202124" : surfaceStyle == .mist ? "FAFBFC" : "FCFAF6")! }
    var raisedRGB: PolarisRGB { PolarisRGB(hex: isDark ? "292A2D" : surfaceStyle == .mist ? "FFFFFF" : "FFFDFA")! }
    var selectionRGB: PolarisRGB { PolarisRGB(hex: isDark ? "343539" : surfaceStyle == .mist ? "E8EAEE" : "EAE6DF")! }
    var hoverRGB: PolarisRGB { PolarisRGB(hex: isDark ? "2B2C30" : surfaceStyle == .mist ? "F0F1F4" : "F2EFE9")! }
    var pressedRGB: PolarisRGB { PolarisRGB(hex: isDark ? "3E4045" : surfaceStyle == .mist ? "DFE2E8" : "E0DAD0")! }
    var surface: Color { surfaceRGB.color }
    var raised: Color { raisedRGB.color }
    var ink: Color { Color(hex: isDark ? "ECEDEF" : surfaceStyle == .mist ? "292C33" : "302D2A") }
    var secondary: Color { Color(hex: isDark ? "B0B3BA" : surfaceStyle == .mist ? "59616C" : "625B51") }
    var muted: Color { Color(hex: isDark ? "A9ADB6" : surfaceStyle == .mist ? "5E6570" : "655E53") }
    var line: Color { Color(hex: isDark ? "37383C" : surfaceStyle == .mist ? "DCDFE4" : "E1DDD6") }
    var hover: Color { hoverRGB.color }
    var pressed: Color { pressedRGB.color }
    var accentRGB: PolarisRGB { customAccentHex.flatMap({ PolarisRGB(hex: $0) }) ?? PolarisRGB(hex: accentStyle.hex)! }
    var accentInkRGB: PolarisRGB { accentRGB.readable(on: [surfaceRGB, raisedRGB, selectionRGB, hoverRGB, pressedRGB]) }
    var action: Color { accentRGB.color }
    var actionText: Color { accentRGB.readableLabel.color }
    var actionInteractionOverlay: Color { accentRGB.readableLabel == .white ? .black : .white }
    var accentInk: Color { accentInkRGB.color }
    var selection: Color { selectionRGB.color }
    var selectionLine: Color { accentInk }
    func readableColor(hex: String, minimum: Double = 4.5) -> Color {
        (PolarisRGB(hex: hex) ?? accentRGB).readable(on: [surfaceRGB, raisedRGB, selectionRGB, hoverRGB, pressedRGB], minimum: minimum).color
    }
}

/// A single preference contract; legacy keys remain intact for downgrade safety.
enum PolarisAppearancePreferences {
    static let customAccent = "custom"
    static let defaultHex = PolarisAccent.klein.hex

    static func palette(in defaults: UserDefaults) -> PolarisPalette? {
        guard let storedAccent = defaults.string(forKey: "polarisAccent"),
              PolarisAccent(rawValue: storedAccent) != nil ||
                (storedAccent == customAccent && defaults.string(forKey: "polarisCustomAccentHex").flatMap({ PolarisRGB(hex: $0) }) != nil) else { return nil }
        return PolarisPalette(surfaceStyle: defaults.string(forKey: "polarisSurface").flatMap(PolarisSurface.init(rawValue:)) ?? .graphite,
                              accentStyle: PolarisAccent(rawValue: storedAccent) ?? .klein,
                              customAccentHex: storedAccent == customAccent ? defaults.string(forKey: "polarisCustomAccentHex") : nil)
    }

    static func migrateIfNeeded(in defaults: UserDefaults, systemIsDark: Bool? = nil) {
        guard defaults.integer(forKey: "polarisAppearanceVersion") < 1 else { return }
        let legacyTheme = (defaults.object(forKey: "appTheme") as? NSNumber).flatMap { AppTheme(rawValue: $0.intValue) }
        if defaults.string(forKey: "polarisSurface").flatMap(PolarisSurface.init(rawValue:)) == nil {
            // Old presets/custom followed system darkness; midnight was always
            // dark. Only consult that appearance when no Polaris surface exists.
            let legacyWasDark = legacyTheme == nil || legacyTheme == .midnight || (systemIsDark ?? AppTheme.systemIsDark)
            defaults.set(legacyWasDark ? "graphite" : "mist", forKey: "polarisSurface")
        }
        if palette(in: defaults) == nil {
            if let legacyTheme {
                let hue = defaults.object(forKey: "customHue") == nil ? 0.55 : defaults.double(forKey: "customHue")
                let legacyColor = legacyTheme == .custom ? Color(hue: hue.isFinite ? max(0, min(1, hue)) : 0.55, saturation: 0.7, brightness: 0.65) : legacyTheme.accent
                if let hex = legacyColor.toHex().flatMap({ PolarisRGB(hex: $0) })?.hex {
                    defaults.set(hex, forKey: "polarisCustomAccentHex")
                    defaults.set(customAccent, forKey: "polarisAccent")
                }
            }
            if palette(in: defaults) == nil { defaults.set(PolarisAccent.klein.rawValue, forKey: "polarisAccent") }
        }
        defaults.set(1, forKey: "polarisAppearanceVersion")
    }

    @discardableResult static func setCustom(_ hex: String, in defaults: UserDefaults) -> Bool {
        guard let color = PolarisRGB(hex: hex) else { return false }
        defaults.set(color.hex, forKey: "polarisCustomAccentHex")
        defaults.set(customAccent, forKey: "polarisAccent")
        return true
    }

    static func restoreDefaultAccent(in defaults: UserDefaults) {
        defaults.set(defaultHex, forKey: "polarisCustomAccentHex")
        defaults.set(PolarisAccent.klein.rawValue, forKey: "polarisAccent")
    }
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
