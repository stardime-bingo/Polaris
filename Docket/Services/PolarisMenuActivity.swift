import AppKit
import Observation

/// Shares one compact slot between the brand artwork and sync feedback.
/// Only a real, visible sync drives frames; idle owns no timer.
final class PolarisMenuActivity {
    private weak var button: NSStatusBarButton?
    private var timer: Timer?
    private var delay: DispatchWorkItem?
    private var busySince: Date?
    private var observers: [NSObjectProtocol] = []
    var isAnimating: Bool { timer?.isValid == true }

    init(button: NSStatusBarButton) {
        self.button = button
        observe()
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        refresh()
    }
    deinit { stop() }
    func stop() {
        timer?.invalidate(); timer = nil
        delay?.cancel(); delay = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers = []
    }
    private func observe() {
        withObservationTracking {
            _ = RemindersSync.shared.isSyncing
            _ = RemindersSync.shared.lastError
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.refresh(); self?.observe() }
        }
    }
    func refresh() {
        timer?.invalidate(); timer = nil
        delay?.cancel(); delay = nil
        let busy = RemindersSync.shared.isSyncing
        if !busy { busySince = nil }
        else if busySince == nil { busySince = Date() }
        draw(phase: nil)
        let motion = UserDefaults.standard.object(forKey: "polarisMotionEnabled") as? Bool ?? true
        guard busy, motion, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let start = busySince, Date().timeIntervalSince(start) < 30 else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, RemindersSync.shared.isSyncing else { return }
            self.timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                guard let self else { return }
                guard let button = self.button, !button.isHidden, button.window?.occlusionState.contains(.visible) == true,
                      RemindersSync.shared.isSyncing, Date().timeIntervalSince(start) < 30 else {
                    self.timer?.invalidate(); self.timer = nil; self.draw(phase: nil); return
                }
                self.draw(phase: Date().timeIntervalSince(start) / 1.8 * .pi * 2)
            }
        }
        delay = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 0.25 - Date().timeIntervalSince(start)), execute: work)
    }
    private func draw(phase: Double?) {
        let busy = RemindersSync.shared.isSyncing
        let failed = RemindersSync.shared.lastError != nil
        let logo = PolarisSymbol.menuImage()
        let image = NSImage(size: NSSize(width: 24, height: 18), flipped: false) { _ in
            if let phase {
                for index in 0..<3 {
                    NSColor.black.withAlphaComponent(1 - Double(index) * 0.24).setFill()
                    let angle = phase + Double(index) * .pi * 2 / 3
                    NSBezierPath(ovalIn: NSRect(x: 12 + cos(angle) * 4.5 - 1.5, y: 9 + sin(angle) * 4.5 - 1.5, width: 3, height: 3)).fill()
                }
            } else if busy || failed {
                let icon = NSImage(systemSymbolName: failed ? "exclamationmark.circle" : "arrow.triangle.2.circlepath", accessibilityDescription: nil)
                icon?.draw(in: NSRect(x: 6, y: 3, width: 12, height: 12))
            } else {
                logo.draw(in: NSRect(x: 0, y: 0, width: 24, height: 18))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = busy ? "Polaris，正在同步" : failed ? "Polaris，同步失败" : "Polaris"
        button?.image = image
    }
}
