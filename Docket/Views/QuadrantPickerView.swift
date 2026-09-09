// QuadrantPickerView.swift
// Docket — macOS Menu Bar Task Manager
// Created by @santoru

import SwiftUI

/// 2×2 grid picker for assigning a task to an Eisenhower quadrant.
struct QuadrantPickerView: View {
    @Binding var quadrant: Quadrant?
    @Environment(\.polarisPalette) private var palette

    @AppStorage("matrixDoFirstLabel") private var doFirstLabel = "优先推进"
    @AppStorage("matrixScheduleLabel") private var scheduleLabel = "持续投入"
    @AppStorage("matrixDelegateLabel") private var delegateLabel = "委派协作"
    @AppStorage("matrixEliminateLabel") private var eliminateLabel = "暂时放下"

    private func label(for q: Quadrant) -> String {
        switch q {
        case .doFirst: doFirstLabel
        case .schedule: scheduleLabel
        case .delegate: delegateLabel
        case .eliminate: eliminateLabel
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.matrix).font(.system(size: 11.5)).foregroundStyle(palette.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(Quadrant.allCases) { q in
                    Button { quadrant = quadrant == q ? nil : q } label: {
                        HStack(spacing: 4) {
                            Image(systemName: q.icon).font(.system(size: 10))
                            Text(label(for: q)).font(.system(size: 11, weight: .regular))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 32)
                        .background(RoundedRectangle(cornerRadius: 5).fill(quadrant == q ? palette.selection : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(quadrant == q ? palette.accentInk.opacity(0.3) : .clear, lineWidth: 0.5))
                        .foregroundStyle(quadrant == q ? palette.accentInk : palette.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(GoalControlStyle()).accessibilityAddTraits(quadrant == q ? .isSelected : [])
                }
            }
        }
    }
}
