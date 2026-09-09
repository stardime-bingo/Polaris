// MatrixView.swift
// Docket — macOS Menu Bar Task Manager
// Created by @santoru

import SwiftUI

/// Eisenhower Matrix view with free-positioned, draggable task pills.
///
/// Design notes:
///  • Quadrants use ultra-subtle tinted fills + hairline borders for a quiet,
///    professional feel — colour identifies, doesn't shout.
///  • Pills truncate text natively via SwiftUI; on hover, long titles scroll
///    horizontally so the full text becomes readable without opening the task.
///  • Pills cannot fully overlap — a per-quadrant rect-overlap resolver
///    spirals later pills outward until they no longer intersect.
///  • Pills are clamped to stay fully inside the quadrant border, derived
///    from the real pill geometry (label length × line count).
///  • Cross-quadrant drags preserve the perpendicular axis so pills feel
///    like they slid across the boundary.
///  • Bottom-row pills can be dragged out of the matrix to remove their
///    quadrant assignment (return to "Unassigned").
struct MatrixView: View {
    @Binding var path: [NavDestination]
    var store = Store.shared
    @Environment(\.polarisPalette) private var palette

    @AppStorage("matrixDoFirstColor") private var doFirstColor = "#EF4444"
    @AppStorage("matrixScheduleColor") private var scheduleColor = "#3B82F6"
    @AppStorage("matrixDelegateColor") private var delegateColor = "#F59E0B"
    @AppStorage("matrixEliminateColor") private var eliminateColor = "#9CA3AF"
    @AppStorage("matrixDoFirstLabel") private var doFirstLabel = "优先推进"
    @AppStorage("matrixScheduleLabel") private var scheduleLabel = "持续投入"
    @AppStorage("matrixDelegateLabel") private var delegateLabel = "委派协作"
    @AppStorage("matrixEliminateLabel") private var eliminateLabel = "暂时放下"
    @AppStorage("matrixLabelLength") private var matrixLabelLength = 14
    @AppStorage("matrixLineCount") private var matrixLineCount = 1
    @AppStorage("matrixShowAxes") private var matrixShowAxes = true
    @AppStorage("matrixShowBadges") private var matrixShowBadges = true

    /// True while any quadrant pill is mid-drag. Drives the visibility of
    /// the empty Unassigned drop zone so it only appears when there's
    /// actually something to drop.
    @State private var isAnyPillDragging = false

    private var accent: Color { palette.accentInk }

    private func quadrantColor(_ q: Quadrant) -> Color {
        switch q {
        case .doFirst: Color(hex: doFirstColor)
        case .schedule: Color(hex: scheduleColor)
        case .delegate: Color(hex: delegateColor)
        case .eliminate: Color(hex: eliminateColor)
        }
    }

    private func quadrantLabel(_ q: Quadrant) -> String {
        switch q {
        case .doFirst: doFirstLabel
        case .schedule: scheduleLabel
        case .delegate: delegateLabel
        case .eliminate: eliminateLabel
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header (fixed)
            HStack {
                Button { path.removeLast() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                        .frame(width: 32, height: 32)
                }.buttonStyle(GoalControlStyle()).accessibilityLabel("返回")
                Spacer()
                Text(L10n.eisenhowerMatrix).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.ink)
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)

            Divider()

            VScroll {
                VStack(spacing: 0) {
                    Spacer().frame(height: 14)

                    if matrixShowAxes { axisHeader }

                    HStack(spacing: 0) {
                        if matrixShowAxes { yAxisLabels }

                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                quadrantBox(.doFirst)
                                quadrantBox(.schedule)
                            }
                            HStack(spacing: 4) {
                                quadrantBox(.delegate)
                                quadrantBox(.eliminate)
                            }
                        }
                    }
                    .padding(.horizontal, 10)

                    unassignedSection
                }
            }
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Axis Labels

    private var axisHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 16)
            HStack(spacing: 4) {
                axisLabel(L10n.axisUrgent)
                axisLabel(L10n.axisNotUrgent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var yAxisLabels: some View {
        VStack(spacing: 4) {
            verticalAxisLabel(L10n.axisImportant).frame(height: 140)
            verticalAxisLabel("不重要").frame(height: 140)
        }
        .frame(width: 16)
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(palette.secondary)
            .frame(maxWidth: .infinity)
    }

    private func verticalAxisLabel(_ text: String) -> some View {
        VStack(spacing: 1) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, c in
                Text(String(c))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    // MARK: - Quadrant Box

    private func quadrantBox(_ quadrant: Quadrant) -> some View {
        let tasks = store.activeTasks.filter { $0.quadrant == quadrant }
        let color = quadrantColor(quadrant)
        let label = quadrantLabel(quadrant)

        return GeometryReader { geo in
            let resolved = resolvePositions(for: tasks, in: geo.size)

            ZStack(alignment: .topLeading) {
                // Background — quiet tinted fill + hairline border.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(color.opacity(0.18), lineWidth: 0.75)
                    )

                // Empty-state hint — only shown when the quadrant has no pills.
                if tasks.isEmpty {
                    Text(L10n.dropTasksHere)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }

                // Color identifies the quadrant; its title stays legible for custom colors.
                HStack(spacing: 5) {
                    Image(systemName: quadrant.icon)
                        .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(color)
                    Text(label)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(palette.ink)
                        .lineLimit(1).truncationMode(.tail).help(label)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.trailing, matrixShowBadges && !tasks.isEmpty ? 28 : 0)
                .padding(.vertical, 6)

                // Count badge — minimal pill, top-right.
                if matrixShowBadges && !tasks.isEmpty {
                    Text("\(tasks.count)")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(color.opacity(0.14)))
                        .position(x: geo.size.width - 16, y: 13)
                }

                // Tasks — positions resolved by parent so they never fully overlap.
                ForEach(Array(tasks.enumerated()), id: \.element.id) { idx, item in
                    TaskDot(
                        item: item,
                        quadrant: quadrant,
                        color: color,
                        maxChars: matrixLabelLength,
                        lineCount: matrixLineCount,
                        bounds: geo.size,
                        initialPosition: resolved[idx],
                        isAnyPillDragging: $isAnyPillDragging,
                        onTap: { path.append(.detail(item)) }
                    )
                }
            }
            .dropDestination(for: String.self) { items, _ in
                for idString in items {
                    if let uuid = UUID(uuidString: idString) {
                        // No withAnimation — the target view is freshly created
                        // and its seedPosition would otherwise animate from
                        // .zero (the top-left corner) under an active transaction.
                        store.mutate(uuid) { item in
                            item.quadrant = quadrant
                            item.matrixX = 0.5
                            item.matrixY = 0.5
                        }
                    }
                }
                return true
            }
        }
        .frame(height: 140)
    }

    // MARK: - Anti-Collision

    /// Compute on-screen positions for the given tasks. Delegates to the pure
    /// `MatrixLayout` resolver (which is unit-tested) after mapping each task's
    /// stored fractional coordinates into seed points.
    private func resolvePositions(for tasks: [TodoItem], in size: CGSize) -> [CGPoint] {
        let seeds = tasks.map { CGPoint(x: $0.matrixX ?? 0.5, y: $0.matrixY ?? 0.5) }
        return MatrixLayout.resolvePositions(seeds: seeds, in: size,
                                             maxChars: matrixLabelLength, lineCount: matrixLineCount)
    }

    // MARK: - Unassigned

    private var unassignedSection: some View {
        let unassigned = store.activeTasks.filter { $0.quadrant == nil }
        // Show the section if (a) there are unassigned tasks parked there,
        // or (b) the user is currently dragging a quadrant pill — in which
        // case we surface the drop zone as a visible affordance.
        let shouldShow = !unassigned.isEmpty || isAnyPillDragging

        return Group {
            if shouldShow {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L10n.unassigned)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.secondary)
                        Spacer()
                        if !unassigned.isEmpty {
                            Text("\(unassigned.count)")
                                .font(.system(size: 10, weight: .medium).monospacedDigit())
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    .padding(.horizontal, 16)

                    if unassigned.isEmpty {
                        // Empty hint — shown only while shouldShow, i.e. during drag.
                        HStack {
                            Spacer()
                            Text(L10n.dropToRemove)
                                .font(.system(size: 11))
                                .foregroundStyle(palette.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(dropZoneBackground)
                        .padding(.horizontal, 16)
                    } else {
                        // Pills, with the dashed drop zone fading in behind them
                        // while a quadrant pill is being dragged.
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(unassigned) { item in
                                    Button { path.append(.detail(item)) } label: {
                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill(priorityColor(item.priority))
                                                .frame(width: 5, height: 5)
                                            Text(item.title)
                                                .font(.system(size: 11, weight: .medium))
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                        }
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(.regularMaterial)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .strokeBorder(.quaternary, lineWidth: 0.5)
                                        )
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: 140)
                                    }
                                    .buttonStyle(.plain)
                                    .draggable(item.id.uuidString)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }
                        .frame(minHeight: 36)
                        .background(dropZoneBackground)
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
                .transition(.opacity)
                .dropDestination(for: String.self) { items, _ in
                    for idString in items {
                        if let uuid = UUID(uuidString: idString) {
                            // No withAnimation — see note in quadrantBox.dropDestination.
                            store.mutate(uuid) { item in
                                item.quadrant = nil
                                item.matrixX = nil
                                item.matrixY = nil
                            }
                        }
                    }
                    return true
                }
            }
        }
    }

    /// Dashed-outline + tinted-fill background that fades in while a
    /// quadrant pill is being dragged. Used by both the empty hint and the
    /// populated pill strip so the drop affordance is consistent.
    @ViewBuilder
    private var dropZoneBackground: some View {
        if isAnyPillDragging {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.quaternary.opacity(0.18))
                )
                .transition(.opacity)
        }
    }

    private func priorityColor(_ p: Priority) -> Color { p.color }
}

// MARK: - Task Dot

/// A draggable task pill rendered inside a quadrant. The pill seeds its
/// position from the parent (which has already run the anti-collision pass),
/// so two pills with identical stored coordinates will never sit exactly on
/// top of each other. The pill also re-seats itself when the parent recomputes
/// positions (e.g., after a window resize or a setting change).
struct TaskDot: View {
    let item: TodoItem
    let quadrant: Quadrant
    let color: Color
    let maxChars: Int
    let lineCount: Int
    let bounds: CGSize
    /// `nil` = position not yet computed by the parent (use stored matrixX/Y).
    let initialPosition: CGPoint?
    @Binding var isAnyPillDragging: Bool
    let onTap: () -> Void

    /// Pill centre, in source-quadrant local coordinates.
    @State private var position: CGPoint = .zero
    /// Pill centre at the moment the current drag started — anchor for translation deltas.
    @State private var dragStartPosition: CGPoint?
    @State private var isDragging = false
    @State private var isHovering = false
    @State private var dragMaxDistance: CGFloat = 0

    /// Width budget for the title text. Capped to the available container so
    /// the pill itself never exceeds the quadrant box.
    private var textMaxWidth: CGFloat {
        let raw = max(36, CGFloat(maxChars) * 5.6)
        let cap = max(20, bounds.width - 26 - 8)
        return min(raw, cap)
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Group {
                if lineCount == 1 {
                    // Single-line: marquee scrolls on hover when truncated.
                    // Suppress while dragging so the title doesn't slide under the cursor.
                    MarqueeText(
                        text: item.title,
                        font: .system(size: 10, weight: .medium),
                        maxWidth: textMaxWidth,
                        isHovering: isHovering && !isDragging
                    )
                } else {
                    Text(item.title)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(lineCount)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: textMaxWidth, alignment: .leading)
                }
            }
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(color.opacity(isDragging ? 0.45 : 0.18), lineWidth: 0.6)
        )
        .shadow(
            color: .black.opacity(isDragging ? 0.18 : 0.06),
            radius: isDragging ? 6 : 1.5,
            x: 0,
            y: isDragging ? 3 : 0.5
        )
        .scaleEffect(isDragging ? 1.06 : (isHovering ? 1.02 : 1.0))
        // Implicit animation scope MUST come before .position so cursor-following
        // updates aren't subjected to a spring (which would feel like the pill is
        // lagging or "falling" toward the cursor).
        .animation(.spring(duration: 0.2), value: isDragging)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .position(x: position.x, y: position.y)
        .zIndex(isDragging ? 10 : (isHovering ? 5 : 0))
        .onHover { isHovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    let dist = hypot(value.translation.width, value.translation.height)
                    if dist > dragMaxDistance { dragMaxDistance = dist }

                    // Only enter "drag mode" once the cursor has moved a few
                    // points — keeps a still click from triggering a scale-up
                    // flicker, and gives the tap-vs-drag check headroom.
                    if !isDragging && dist >= 3 {
                        dragStartPosition = position
                        isDragging = true
                        // Surface the drag globally so the matrix can reveal
                        // the Unassigned drop zone.
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isAnyPillDragging = true
                        }
                    }

                    if isDragging, let start = dragStartPosition {
                        position = CGPoint(
                            x: start.x + value.translation.width,
                            y: start.y + value.translation.height
                        )
                    }
                }
                .onEnded { value in
                    let totalDistance = dragMaxDistance
                    dragMaxDistance = 0

                    // Treat micro-movements as taps (avoids opening the detail
                    // view when the user wiggles the cursor while clicking).
                    if totalDistance < 4 {
                        isDragging = false
                        dragStartPosition = nil
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isAnyPillDragging = false
                        }
                        onTap()
                        return
                    }

                    handleDragEnd(value: value)
                    isDragging = false
                    dragStartPosition = nil
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isAnyPillDragging = false
                    }
                }
        )
        // Re-seat when the parent recomputes layout (resize, settings change,
        // or a sibling pill moved and our resolved spot shifted).
        // Skipped while dragging so the cursor-follow isn't fought.
        .onChange(of: initialPosition) { _, new in
            guard !isDragging, let new else { return }
            withAnimation(.smooth(duration: 0.25)) { position = new }
        }
        .onAppear {
            // Always seed the position outside any active animation transaction.
            // When this TaskDot is freshly created (e.g. as a result of a
            // cross-quadrant move), the parent's mutate may have been wrapped
            // in withAnimation — without this guard, SwiftUI would animate
            // `position` from its default .zero (top-left corner) to the
            // resolved spot, which reads as the pill "dropping from the top".
            withTransaction(Transaction(animation: nil)) {
                seedPosition()
            }
        }
    }

    // MARK: - Drag end

    private func handleDragEnd(value: DragGesture.Value) {
        guard let start = dragStartPosition else { return }
        let released = CGPoint(x: start.x + value.translation.width,
                               y: start.y + value.translation.height)
        switch MatrixLayout.dropTarget(from: quadrant, releasePoint: released, in: bounds) {
        case .unassigned:
            Store.shared.mutate(item.id) { item in
                item.quadrant = nil
                item.matrixX = nil
                item.matrixY = nil
            }
        case .quadrant(let target) where target == quadrant:
            settleInside(actualX: released.x, actualY: released.y)
        case .quadrant(let target):
            let (x, y) = entryPoint(into: target, finalX: released.x, finalY: released.y)
            let landing = MatrixLayout.clampedPosition(
                CGPoint(x: x * bounds.width, y: y * bounds.height),
                in: bounds, maxChars: maxChars, lineCount: lineCount)
            Store.shared.mutate(item.id) { item in
                item.quadrant = target
                item.matrixX = landing.x / max(bounds.width, 1)
                item.matrixY = landing.y / max(bounds.height, 1)
            }
        }
    }

    /// Persist a new in-quadrant position and animate the pill to it. Uses
    /// `.smooth` (critically damped) so there's no spring overshoot — the
    /// pill simply eases into its final resting place.
    private func settleInside(actualX: CGFloat, actualY: CGFloat) {
        let target = MatrixLayout.clampedPosition(
            CGPoint(x: actualX, y: actualY), in: bounds, maxChars: maxChars, lineCount: lineCount)
        let newX = target.x / max(bounds.width, 1)
        let newY = target.y / max(bounds.height, 1)

        withAnimation(.smooth(duration: 0.22)) {
            position = target
        }
        Store.shared.mutate(item.id) { item in
            item.matrixX = newX
            item.matrixY = newY
        }
    }

    /// Compute the (matrixX, matrixY) the pill should land at when entering
    /// `target` from the given exit-edge coordinates. For axis-aligned moves
    /// the perpendicular axis is preserved (so the pill feels like it slid
    /// across). For diagonal moves the pill lands in the corner of the
    /// target closest to the source quadrant.
    private func entryPoint(into target: Quadrant, finalX: CGFloat, finalY: CGFloat) -> (Double, Double) {
        let xRatio = clamp(finalX / bounds.width, 0.15, 0.85)
        let yRatio = clamp(finalY / bounds.height, 0.15, 0.85)

        switch (quadrant, target) {
        // Axis-aligned: preserve the perpendicular axis.
        case (.doFirst, .schedule), (.delegate, .eliminate):
            return (0.18, yRatio)                     // exited right → enter at left
        case (.schedule, .doFirst), (.eliminate, .delegate):
            return (0.82, yRatio)                     // exited left → enter at right
        case (.doFirst, .delegate), (.schedule, .eliminate):
            return (xRatio, 0.20)                     // exited bottom → enter at top
        case (.delegate, .doFirst), (.eliminate, .schedule):
            return (xRatio, 0.80)                     // exited top → enter at bottom

        // Diagonals: drop into the corner of the target nearest the source.
        case (.doFirst, .eliminate):  return (0.20, 0.20)   // top-left of eliminate
        case (.schedule, .delegate):  return (0.80, 0.20)   // top-right of delegate
        case (.delegate, .schedule):  return (0.20, 0.80)   // bottom-left of schedule
        case (.eliminate, .doFirst):  return (0.80, 0.80)   // bottom-right of doFirst

        default:
            return (0.5, 0.5)
        }
    }

    // MARK: - Position seeding

    private func seedPosition() {
        let seed = initialPosition ?? CGPoint(
            x: (item.matrixX ?? 0.5) * bounds.width,
            y: (item.matrixY ?? 0.5) * bounds.height)
        position = MatrixLayout.clampedPosition(seed, in: bounds, maxChars: maxChars, lineCount: lineCount)
    }

    private func clamp(_ value: Double, _ min: Double, _ max: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }

    private func clamp(_ value: CGFloat, _ min: CGFloat, _ max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }
}

// MARK: - Marquee Text

/// A single-line text view that:
///  • Shows a `…` ellipsis when the natural text width exceeds `maxWidth`.
///  • While `isHovering` is true *and* the text is truncated, smoothly scrolls
///    horizontally so the user can read the full title without opening the task.
struct MarqueeText: View {
    let text: String
    let font: Font
    let maxWidth: CGFloat
    let isHovering: Bool

    @State private var fullWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflows: Bool { fullWidth > maxWidth + 0.5 }

    var body: some View {
        ZStack(alignment: .leading) {
            // Hidden measurer — reports the natural (unconstrained) text width.
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .hidden()
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: MarqueeTextWidthKey.self, value: g.size.width)
                    }
                )

            // Visible text — scrolls when hovering, ellipsis-truncates otherwise.
            if isHovering && overflows {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset)
            } else {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(width: maxWidth, alignment: .leading)
        .clipped()
        .onPreferenceChange(MarqueeTextWidthKey.self) { fullWidth = $0 }
        .onChange(of: isHovering) { _, hovering in
            updateMarquee(hovering: hovering)
        }
        .onChange(of: text) { _, _ in
            if isHovering { updateMarquee(hovering: true) }
        }
    }

    private func updateMarquee(hovering: Bool) {
        if hovering && overflows {
            let distance = fullWidth - maxWidth + 8
            let speed: Double = 28
            let duration = max(1.6, Double(distance) / speed)
            offset = 0
            withAnimation(
                .linear(duration: duration)
                    .delay(0.25)
                    .repeatForever(autoreverses: true)
            ) {
                offset = -distance
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                offset = 0
            }
        }
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
