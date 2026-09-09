import SwiftUI

/// A short, finite celebration. No display link runs while the app is idle.
struct ConfettiOverlay: View {
    let trigger: Int
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.polarisPalette) private var palette
    @State private var pieces: [Piece] = []
    @State private var falling = false
    @State private var lastHandledTrigger = 0

    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat
        let drift: CGFloat
        let size: CGFloat
        let rotation: Double
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(piece.id.isMultiple(of: 3) ? palette.accentInk : palette.ink.opacity(0.7))
                        .frame(width: piece.size, height: piece.size * 0.45)
                        .rotationEffect(.degrees(piece.rotation + (falling ? 180 : 0)))
                        .position(x: geometry.size.width / 2 + piece.x + (falling ? piece.drift : 0),
                                  y: falling ? geometry.size.height * 0.8 : 16)
                        .opacity(falling ? 0 : 0.9)
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: "\(trigger)-\(enabled)-\(reduceMotion)") {
            pieces = []
            falling = false
            guard trigger > lastHandledTrigger else { return }
            lastHandledTrigger = trigger
            guard enabled, !reduceMotion else { return }
            pieces = (0..<24).map { Piece(id: $0, x: .random(in: -100...100), drift: .random(in: -35...35), size: .random(in: 4...7), rotation: .random(in: 0...180)) }
            do {
                try await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeOut(duration: 1.35)) { falling = true }
                try await Task.sleep(for: .milliseconds(1400))
                pieces = []
                falling = false
            } catch {
                // Navigation or another completion cancels this burst.
            }
        }
    }
}
