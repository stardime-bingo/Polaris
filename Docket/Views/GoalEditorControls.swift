import SwiftUI

struct GoalEditorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.polarisPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.secondary)
            content
        }
    }
}

/// The entire row is the menu/button target, including the space between label and value.
struct GoalOptionLabel: View {
    let title: String
    let value: String
    var chevron = true
    @Environment(\.polarisPalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(palette.secondary)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(palette.ink).multilineTextAlignment(.trailing)
            if chevron { Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(palette.muted) }
        }
        .font(.system(size: 12.5))
        .frame(minHeight: 36)
        .frame(maxWidth: .infinity).contentShape(Rectangle())
    }
}

struct GoalControlStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        GoalControlSurface(configuration: configuration, primary: primary)
    }
}

private struct GoalControlSurface: View {
    let configuration: ButtonStyleConfiguration
    let primary: Bool
    @Environment(\.polarisPalette) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovered = false
    var body: some View {
        configuration.label
            .background {
                if primary {
                    RoundedRectangle(cornerRadius: 5).fill(palette.action)
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .fill(palette.accentStyle.values.text == "FFFFFF" ? Color.black : Color.white)
                            .opacity(configuration.isPressed ? 0.14 : hovered ? 0.06 : 0))
                        .padding(.vertical, 3)
                } else {
                    RoundedRectangle(cornerRadius: 5).fill(enabled && configuration.isPressed ? palette.pressed : enabled && hovered ? palette.hover : .clear)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(focused ? palette.accentInk : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovered = $0 }
    }
}
