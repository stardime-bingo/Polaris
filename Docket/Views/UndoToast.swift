// UndoToast.swift
// Docket — macOS Menu Bar Task Manager
// Created by @santoru

import SwiftUI

/// A reversible completion with time to react, including keyboard users.
struct UndoToast: View {
    let message: String
    let trigger: Int
    let onUndo: () -> Void
    @Binding var isVisible: Bool

    @Environment(\.polarisPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var accent: Color { palette.action }

    @State private var dismissTask: DispatchWorkItem?

    var body: some View {
        if isVisible {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.green)

                Text(message)
                    .font(.subheadline.weight(.medium))

                Spacer()

                Button {
                    onUndo()
                    dismiss()
                } label: {
                    Text(L10n.undo)
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(accent))
                        .foregroundStyle(palette.actionText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
            .padding(.horizontal, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onChange(of: trigger) { _, _ in scheduleAutoDismiss() }
            .onAppear { scheduleAutoDismiss() }
            .onHover { hovering in
                if hovering { dismissTask?.cancel() } else { scheduleAutoDismiss() }
            }
            .onDisappear { dismissTask?.cancel() }
        }
    }

    private func scheduleAutoDismiss() {
        dismissTask?.cancel()
        let task = DispatchWorkItem { dismiss() }
        dismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: task)
    }

    private func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { isVisible = false }
    }
}
