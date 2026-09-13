import Foundation
import SwiftUI
import AppKit

func runAppearanceTests() {
    // Known sRGB/WCAG anchors, independent of any palette's chosen presets.
    expectEqual(PolarisRGB(hex: " #aBc ")?.hex, "AABBCC", "short HEX canonicalizes without alpha")
    expectEqual(PolarisRGB(hex: "00ff7F")?.hex, "00FF7F", "six-digit HEX preserves channel values")
    for invalid in ["", "##fff", "0xFFFFFF", "ffff", "FFFFFFFF", "12GG00", "１２３", "AB CD EF"] {
        expect(PolarisRGB(hex: invalid) == nil, "invalid HEX rejected: \(invalid)")
    }

    // HSB is computed from encoded sRGB, with known anchors in every hue sector.
    let hsbAnchors: [(rgb: PolarisRGB, hue: Double, saturation: Double, brightness: Double)] = [
        (PolarisRGB(red: 1, green: 0, blue: 0), 0, 1, 1),
        (PolarisRGB(red: 1, green: 1, blue: 0), 1.0 / 6, 1, 1),
        (PolarisRGB(red: 0, green: 1, blue: 0), 2.0 / 6, 1, 1),
        (PolarisRGB(red: 0, green: 1, blue: 1), 3.0 / 6, 1, 1),
        (PolarisRGB(red: 0, green: 0, blue: 1), 4.0 / 6, 1, 1),
        (PolarisRGB(red: 1, green: 0, blue: 1), 5.0 / 6, 1, 1),
        (PolarisRGB(red: 0.4, green: 0.2, blue: 0.2), 0, 0.5, 0.4),
        (PolarisRGB(red: 0.24, green: 0.36, blue: 0.6), 11.0 / 18, 0.6, 0.6),
        (PolarisRGB(red: 0.5, green: 0.5, blue: 0.5), 0, 0, 0.5),
        (.white, 0, 0, 1),
        (.black, 0, 0, 0)
    ]
    func channelsAreClose(_ first: PolarisRGB, _ second: PolarisRGB, tolerance: Double = 0.000000000001) -> Bool {
        abs(first.red - second.red) <= tolerance &&
        abs(first.green - second.green) <= tolerance &&
        abs(first.blue - second.blue) <= tolerance
    }
    for anchor in hsbAnchors {
        let hsb = anchor.rgb.hsb
        expect(abs(hsb.hue - anchor.hue) < 0.000000000001 &&
               abs(hsb.saturation - anchor.saturation) < 0.000000000001 &&
               abs(hsb.brightness - anchor.brightness) < 0.000000000001,
               "known RGB anchor resolves expected HSB: \(anchor.rgb.hex)")
        expect(channelsAreClose(PolarisRGB(hue: anchor.hue, saturation: anchor.saturation, brightness: anchor.brightness), anchor.rgb),
               "known HSB anchor resolves expected RGB: \(anchor.rgb.hex)")
    }
    let red = PolarisRGB(red: 1, green: 0, blue: 0)
    for hue in [0.0, 1, -1, 2, -2, Double.greatestFiniteMagnitude] {
        expectEqual(PolarisRGB(hue: hue, saturation: 1, brightness: 1), red, "whole hue turns wrap to red")
    }
    expect(channelsAreClose(PolarisRGB(hue: -0.25, saturation: 1, brightness: 1), PolarisRGB(red: 0.5, green: 0, blue: 1)),
           "negative fractional hue wraps around the color wheel")
    expect(channelsAreClose(PolarisRGB(hue: 1.25, saturation: 1, brightness: 1), PolarisRGB(red: 0.5, green: 1, blue: 0)),
           "positive fractional hue wraps around the color wheel")
    expectEqual(PolarisRGB(hue: 0.4, saturation: -1, brightness: 2), .white, "saturation and brightness clamp to channel limits")
    expectEqual(PolarisRGB(hue: 0.4, saturation: 2, brightness: -1), .black, "negative brightness stays black")
    expectEqual(PolarisRGB(hue: 0, saturation: 2, brightness: 2), red, "excess saturation and brightness clamp to one")
    for invalid in [Double.nan, .infinity, -.infinity] {
        expectEqual(PolarisRGB(hue: invalid, saturation: 1, brightness: 1), red, "non-finite hue safely resolves to zero")
        expectEqual(PolarisRGB(hue: 0.4, saturation: invalid, brightness: 1), .white, "non-finite saturation safely resolves to zero")
        expectEqual(PolarisRGB(hue: 0.4, saturation: 1, brightness: invalid), .black, "non-finite brightness safely resolves to zero")
    }
    for hue in [-Double.leastNonzeroMagnitude, Double.leastNonzeroMagnitude, 1.0.nextDown, 1.0.nextUp] {
        for saturation in [0.0, Double.leastNonzeroMagnitude, 0.5, 1] {
            for brightness in [0.0, Double.leastNonzeroMagnitude, 0.5, 1] {
                let rgb = PolarisRGB(hue: hue, saturation: saturation, brightness: brightness)
                let hsb = rgb.hsb
                expect(hsb.hue.isFinite && hsb.saturation.isFinite && hsb.brightness.isFinite,
                       "hue seam, achromatic, and subnormal inputs never produce NaN")
                expect(channelsAreClose(PolarisRGB(hue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness), rgb),
                       "HSB boundary colors survive an RGB round trip")
            }
        }
    }

    // An independent AppKit reference catches color-space or component mistakes.
    // The grid includes near-black/white colors and every RGB maximum/minimum tie.
    for r in [0.0, 0.001, 0.2, 0.5, 0.8, 0.999, 1] {
        for g in [0.0, 0.001, 0.2, 0.5, 0.8, 0.999, 1] {
            for b in [0.0, 0.001, 0.2, 0.5, 0.8, 0.999, 1] {
                let original = PolarisRGB(red: r, green: g, blue: b)
                let hsb = original.hsb
                expect(hsb.hue.isFinite && hsb.saturation.isFinite && hsb.brightness.isFinite &&
                       hsb.hue >= 0 && hsb.hue < 1 && (0...1).contains(hsb.saturation) && (0...1).contains(hsb.brightness),
                       "HSB components stay finite and normalized")
                expect(channelsAreClose(PolarisRGB(hue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness), original),
                       "sRGB to HSB to sRGB round trip stays within 1e-12")
                let native = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
                var nativeHue: CGFloat = 0
                var nativeSaturation: CGFloat = 0
                var nativeBrightness: CGFloat = 0
                native.getHue(&nativeHue, saturation: &nativeSaturation, brightness: &nativeBrightness, alpha: nil)
                expect(abs(hsb.saturation - Double(nativeSaturation)) < 0.000001 && abs(hsb.brightness - Double(nativeBrightness)) < 0.000001,
                       "HSB saturation and brightness agree with NSColor sRGB")
                if hsb.saturation > 0 {
                    let hueDifference = abs(hsb.hue - Double(nativeHue))
                    expect(min(hueDifference, 1 - hueDifference) < 0.000001, "chromatic hue agrees with NSColor sRGB")
                }
            }
        }
    }

    expect(abs(PolarisRGB.white.contrast(with: .black) - 21) < 0.000001, "black/white contrast is 21:1")
    expect(abs(PolarisRGB(hex: "FF0000")!.luminance - 0.2126) < 0.000001, "sRGB red luminance is 0.2126")
    expect(abs(PolarisRGB(hex: "808080")!.luminance - 0.2158605) < 0.000001, "sRGB midpoint uses gamma decoding")
    expectEqual(PolarisRGB.white.readableLabel, .black, "white fill uses black text")
    expectEqual(PolarisRGB.black.readableLabel, .white, "black fill uses white text")
    expectEqual(PolarisRGB.black.readable(on: [.white]), .black, "already-readable color is not recolored")

    // Sweep channel extremes and midtones across every real content surface.
    // Stored/fill color must stay exact; text and fine line contrast must pass.
    for surface in PolarisSurface.allCases {
        for red in stride(from: 0, through: 255, by: 51) {
            for green in stride(from: 0, through: 255, by: 51) {
                for blue in stride(from: 0, through: 255, by: 51) {
                    let hex = String(format: "%02X%02X%02X", red, green, blue)
                    let palette = PolarisPalette(surfaceStyle: surface, customAccentHex: hex)
                    expectEqual(palette.accentRGB.hex, hex, "custom original is retained on \(surface.rawValue)")
                    expect(palette.accentRGB.contrast(with: palette.accentRGB.readableLabel) >= 4.5,
                           "button label stays readable for \(hex)")
                    for background in [palette.surfaceRGB, palette.raisedRGB, palette.selectionRGB, palette.hoverRGB, palette.pressedRGB, palette.goalSelectionRGB, palette.goalPressedRGB] {
                        expect(palette.accentInkRGB.contrast(with: background) >= 4.5 - 0.000001,
                               "accent text meets 4.5:1 on \(surface.rawValue) for \(hex)")
                    }
                }
            }
        }
        for preset in PolarisAccent.allCases {
            let palette = PolarisPalette(surfaceStyle: surface, accentStyle: preset)
            expectEqual(palette.accentRGB.hex, preset.hex, "six preset fills keep their exact color")
        }
        for hex in ["EF4444", "3B82F6", "F59E0B", "9CA3AF", "C95151", "B57826", "FFFFFF", "000000"] {
            let palette = PolarisPalette(surfaceStyle: surface)
            expect(palette.annotationInkRGB(hex: hex).contrast(with: palette.annotationSurfaceRGB(hex: hex)) >= 4.5 - 0.000001,
                   "category and deadline annotation text remains readable on its actual fill")
        }
    }
    let corrected = PolarisRGB.white.readable(on: [.white])
    expect(abs(corrected.contrast(with: .white) - 4.5) < 0.000001, "correction stops at necessary contrast, not an arbitrary darker color")
    let badCustom = PolarisPalette(accentStyle: .rose, customAccentHex: "invalid")
    expectEqual(badCustom.accentRGB.hex, PolarisAccent.rose.hex, "corrupt custom color safely falls back to selected preset")

    let suite = "com.bingowu.polaris.tests.appearance.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    func reset() { defaults.removePersistentDomain(forName: suite) }

    PolarisAppearancePreferences.migrateIfNeeded(in: defaults, systemIsDark: false)
    expectEqual(PolarisAppearancePreferences.palette(in: defaults)?.surfaceStyle, .graphite, "new install preserves graphite default")
    expectEqual(PolarisAppearancePreferences.palette(in: defaults)?.accentStyle, .klein, "new install preserves blue default")
    expect(defaults.object(forKey: "appTheme") == nil, "migration does not manufacture old theme preferences")

    reset()
    defaults.set(AppTheme.custom.rawValue, forKey: "appTheme")
    defaults.set(0.5, forKey: "customHue")
    defaults.set(0.23, forKey: "customSat")
    defaults.set(false, forKey: "polarisGlassEnabled")
    defaults.set("unrelated-test-binding", forKey: "remindersListID")
    PolarisAppearancePreferences.migrateIfNeeded(in: defaults, systemIsDark: false)
    expectEqual(defaults.string(forKey: "polarisAccent"), "custom", "legacy custom becomes active custom accent")
    expectEqual(defaults.string(forKey: "polarisCustomAccentHex"), "32A6A6", "legacy custom recovers the actual old hue-based accent")
    expectEqual(defaults.double(forKey: "customHue"), 0.5, "legacy hue remains intact")
    expectEqual(defaults.double(forKey: "customSat"), 0.23, "legacy background intensity remains intact")
    expectEqual(defaults.integer(forKey: "appTheme"), AppTheme.custom.rawValue, "legacy theme remains intact")
    expect(!defaults.bool(forKey: "polarisGlassEnabled"), "migration keeps glass preference")
    expectEqual(defaults.string(forKey: "remindersListID"), "unrelated-test-binding", "migration leaves sync binding untouched")

    expect(PolarisAppearancePreferences.setCustom("#FEFCDC", in: defaults), "custom choice accepted")
    defaults.synchronize()
    let reopened = UserDefaults(suiteName: suite)!
    expectEqual(PolarisAppearancePreferences.palette(in: reopened)?.accentRGB.hex, "FEFCDC", "fresh preference reader restores exact custom color")
    expect(!PolarisAppearancePreferences.setCustom("#not-a-color", in: defaults), "invalid custom choice rejected")
    expectEqual(PolarisAppearancePreferences.palette(in: defaults)?.accentRGB.hex, "FEFCDC", "invalid input does not overwrite valid selection")
    let palette = PolarisAppearancePreferences.palette(in: defaults)!
    expectEqual(ThemeManager.resolvedAccent(themeRaw: AppTheme.midnight.rawValue, customHue: 0.9, defaults: defaults).toHex(), palette.accentInk.toHex(), "legacy accent entry point uses active Polaris palette")
    expectEqual(ThemeManager.resolvedBackground(themeRaw: AppTheme.midnight.rawValue, customHue: 0.9, customSat: 1, defaults: defaults).toHex(), palette.surface.toHex(), "legacy background entry point uses active Polaris surface")
    expectEqual(ThemeManager.resolvedIsDark(themeRaw: AppTheme.midnight.rawValue, defaults: defaults), false, "legacy darkness lookup follows chosen light surface")
    PolarisAppearancePreferences.restoreDefaultAccent(in: defaults)
    expectEqual(PolarisAppearancePreferences.palette(in: defaults)?.accentRGB.hex, "002FA7", "restore resets only theme accent")
    expectEqual(defaults.string(forKey: "polarisSurface"), "mist", "restore retains chosen surface")
    expectEqual(defaults.double(forKey: "customSat"), 0.23, "restore retains legacy preference backup")
    expectEqual(defaults.string(forKey: "remindersListID"), "unrelated-test-binding", "restore leaves sync binding untouched")

    reset()
    defaults.set(AppTheme.custom.rawValue, forKey: "appTheme")
    defaults.set(0.8, forKey: "customHue")
    defaults.set("warm", forKey: "polarisSurface")
    defaults.set("lime", forKey: "polarisAccent")
    PolarisAppearancePreferences.migrateIfNeeded(in: defaults, systemIsDark: true)
    expectEqual(defaults.string(forKey: "polarisAccent"), "lime", "explicit Polaris preset wins over dormant legacy theme")
    expectEqual(defaults.string(forKey: "polarisSurface"), "warm", "explicit warm surface wins over legacy custom in system dark mode")
    defaults.set("rose", forKey: "polarisAccent")
    PolarisAppearancePreferences.migrateIfNeeded(in: defaults, systemIsDark: false)
    expectEqual(defaults.string(forKey: "polarisAccent"), "rose", "repeated migration never replays legacy values")

    for legacyTheme in [AppTheme.custom, .lavender] {
        reset()
        defaults.set(legacyTheme.rawValue, forKey: "appTheme")
        PolarisAppearancePreferences.migrateIfNeeded(in: defaults, systemIsDark: true)
        expectEqual(defaults.string(forKey: "polarisSurface"), "graphite", "legacy custom/preset preserves system dark appearance")
        expectEqual(defaults.integer(forKey: "appTheme"), legacyTheme.rawValue, "dark migration keeps the legacy theme preference")
    }

    reset()
    PolarisAppearancePreferences.migrateIfNeeded(in: defaults, systemIsDark: true)
    expectEqual(defaults.string(forKey: "polarisSurface"), "graphite", "new install stays graphite regardless of system appearance")

    reset()
    defaults.set(AppTheme.midnight.rawValue, forKey: "appTheme")
    PolarisAppearancePreferences.migrateIfNeeded(in: defaults, systemIsDark: false)
    expectEqual(defaults.string(forKey: "polarisSurface"), "graphite", "legacy midnight keeps a dark surface")
    expectEqual(defaults.string(forKey: "polarisAccent"), "custom", "legacy non-Polaris preset is retained as a custom color")
}
