// ThemedToggle.swift
// Docket — macOS Menu Bar Task Manager
// Created by @santoru

import SwiftUI

/// A native switch with its label and accessibility state kept together.
struct ThemedToggle: View {
    let label: String
    @Binding var isOn: Bool
    @Environment(\.polarisPalette) private var palette
    var animated: Bool = false

    var body: some View {
        Toggle(isOn: $isOn) { HStack { Text(label); Spacer() } }
            .font(.system(size: 12.5)).toggleStyle(.switch).controlSize(.small).tint(palette.action)
            .frame(minHeight: 36)
            .accessibilityLabel(label)
    }
}
