import SwiftUI

/// A single local pulse around the completion check, never a full-panel effect.
/// Stroke rendering adapted from Pow's PulseStrokeAnimationModifier (MIT).
/// Copyright (c) 2023 Emerge Tools, Inc. See Resources/Pow-LICENSE.txt.
/// Source: EmergeTools/Pow@1b4b1dda28c50b95f0872927ee2226fe8b58950e
struct ConfettiOverlay: View {
    let trigger: Int
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.polarisPalette) private var palette
    @State private var progress: CGFloat = 0
    @State private var isActive = false
    @State private var lastHandledTrigger = 0

    private struct PulseIdentity: Equatable {
        let trigger: Int
        let enabled: Bool
        let reduceMotion: Bool
    }

    var body: some View {
        Color.clear
            .frame(width: 18, height: 18)
            .overlay {
                if isActive {
                    CompletionPulse(progress: progress, color: palette.accentInk)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: PulseIdentity(trigger: trigger, enabled: enabled, reduceMotion: reduceMotion)) {
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) {
                    isActive = false
                    progress = 0
                }
                guard trigger > lastHandledTrigger else { return }
                lastHandledTrigger = trigger
                guard enabled, !reduceMotion else { return }
                withTransaction(reset) { isActive = true }
                do {
                    // Commit the initial ring before its one-shot animation.
                    try await Task.sleep(for: .milliseconds(20))
                    try Task.checkCancellation()
                    withAnimation(.linear(duration: 0.6)) { progress = 1 }
                    try await Task.sleep(for: .milliseconds(600))
                    try Task.checkCancellation()
                    isActive = false
                } catch {
                    // A newer trigger owns the state. Never clear its pulse here.
                }
            }
    }
}

/// Pow's expanding inset stroke, reduced to one 18–34 pt circle. The original
/// particle layer, queue, blur and brightness changes are intentionally absent;
/// a bounded easing curve keeps progress finite through the full 600 ms.
private struct CompletionPulse: View, Animatable {
    var progress: CGFloat
    let color: Color

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let remaining = 1 - min(max(progress, 0), 1)
        let expansion = 8 * (1 - remaining * remaining * remaining)
        Circle()
            .inset(by: -expansion)
            .strokeBorder(color, lineWidth: 0.5 + remaining)
            .opacity(Double(remaining * remaining) * 0.65)
    }
}
