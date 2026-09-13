// UndoToast.swift
// Docket — macOS Menu Bar Task Manager
// Created by @santoru

import SwiftUI

/// A compact completion receipt. Each new completion gets its own 2.2 seconds.
struct UndoToast: View {
    let message: String
    let trigger: Int
    let onUndo: () -> Void
    @Binding var isVisible: Bool

    @AppStorage("showConfetti") private var showConfetti = true
    @AppStorage("polarisMotionEnabled") private var motion = true
    @Environment(\.polarisPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isVisible {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.accentInk)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(palette.accentInk.opacity(0.09)))
                        .overlay {
                            ConfettiOverlay(trigger: trigger, enabled: showConfetti && motion)
                        }
                        .accessibilityHidden(true)

                    Text(message)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .layoutPriority(1)

                    Spacer(minLength: 8)

                    Button {
                        onUndo()
                        dismiss()
                    } label: {
                        Text(L10n.undo)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(palette.ink)
                            .padding(.horizontal, 2)
                            .frame(height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(minWidth: 180, maxWidth: 220)
                .frame(height: 32)
                .fixedSize(horizontal: true, vertical: true)
                .background(Capsule().fill(palette.raised))
                .overlay(Capsule().strokeBorder(palette.line, lineWidth: 0.5))
                .shadow(color: palette.ink.opacity(0.08), radius: 5, y: 2)
                .transition(.opacity)
                .task(id: trigger) {
                    do {
                        try await Task.sleep(for: .milliseconds(2200))
                        try Task.checkCancellation()
                        dismiss()
                    } catch {
                        // Replacement completions and navigation cancel this timer.
                    }
                }
            }
        }
        .animation(motion && !reduceMotion ? .easeOut(duration: 0.14) : nil, value: isVisible)
    }

    private func dismiss() {
        isVisible = false
    }
}
