import SwiftUI

struct PolarisActivityView: View {
    var active: Bool
    @Environment(\.polarisPalette) private var palette
    var body: some View {
        if active {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                ZStack {
                    ForEach(0..<3) { index in
                        Circle().fill(palette.accentInk.opacity(1 - Double(index) * 0.24))
                            .frame(width: 3, height: 3).offset(y: -4.5)
                            .rotationEffect(.degrees(Double(index) * 120))
                    }
                }.frame(width: 16, height: 16)
                    .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8 * 360))
            }.accessibilityHidden(true)
        } else {
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11))
                .frame(width: 16, height: 16).accessibilityHidden(true)
        }
    }
}

struct PolarisSyncStatus: View {
    var visible = true
    @AppStorage("remindersSyncEnabled") private var enabled = false
    @AppStorage("polarisMotionEnabled") private var motion = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.polarisPalette) private var palette
    @State private var panelOpen = false
    @State private var animated = false
    private var sync: RemindersSync { .shared }
    private var connected: Bool {
        !DocketRuntime.isPreview && enabled && sync.isAuthorized &&
        Store.shared.lists.contains { $0.remindersCalendarId != nil }
    }
    private var title: String {
        if !DocketRuntime.isPreview && enabled && !sync.isAuthorized { return "待授权" }
        if !connected { return "本地保存" }
        if sync.isSyncing { return "同步中…" }
        if sync.lastError != nil { return "同步失败" }
        return sync.lastSyncDate == nil ? "待同步" : "已同步"
    }
    private var shouldAnimate: Bool { visible && connected && sync.isSyncing && panelOpen && motion && !reduceMotion }
    var body: some View {
        Button { if connected && !sync.isSyncing { sync.syncAll() } } label: {
            HStack(spacing: 4) {
                if connected && sync.isSyncing { PolarisActivityView(active: animated) }
                else {
                    Image(systemName: connected && sync.lastError != nil ? "exclamationmark.circle" : connected ? "checkmark.icloud" : "internaldrive")
                        .font(.system(size: 11)).frame(width: 16, height: 16)
                }
                Text(title).font(.system(size: 10.5)).frame(width: 58, alignment: .leading)
            }.foregroundStyle(connected && sync.lastError != nil ? palette.accentInk : palette.muted)
                .frame(height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!connected || sync.isSyncing)
            .accessibilityLabel(connected ? "\(title)，同步提醒事项" : title == "待授权" ? "提醒事项待授权，请前往更多设置" : "目标保存在本机")
            .help(sync.lastError ?? (connected ? "同步 Apple 提醒事项" : "可在更多设置中连接 Apple 提醒事项"))
            .onAppear { panelOpen = AppDelegate.shared?.isPopoverShown == true }
            .onDisappear { panelOpen = false; animated = false }
            .onReceive(NotificationCenter.default.publisher(for: .popoverDidOpen)) { _ in panelOpen = true }
            .onReceive(NotificationCenter.default.publisher(for: .popoverDidClose)) { _ in panelOpen = false }
            .task(id: shouldAnimate) {
                animated = false
                guard shouldAnimate else { return }
                do {
                    try await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    animated = true
                    try await Task.sleep(for: .seconds(30))
                    animated = false
                } catch { /* A newer task owns the state after cancellation. */ }
            }
    }
}
