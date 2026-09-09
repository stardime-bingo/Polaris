// Docket — created by @santoru; adapted for Polaris.
import SwiftUI

struct CompletedTasksView: View {
    @Binding var path: [NavDestination]
    var store = Store.shared
    @Environment(\.polarisPalette) private var palette
    @Environment(\.polarisNow) private var now
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { path.removeLast() } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }.buttonStyle(GoalControlStyle()).accessibilityLabel("返回设置")
                Spacer(); Text("已达成目标").font(.system(size: 12.5, weight: .medium)); Spacer()
                Text("\(store.completedTasks.count)").font(.system(size: 11)).foregroundStyle(palette.muted).frame(width: 24)
            }.padding(.horizontal, 13).frame(height: 48)
            palette.line.frame(height: 0.5)
            if store.completedTasks.isEmpty {
                Spacer()
                VStack(spacing: 10) { Image(systemName: "checkmark.circle").font(.system(size: 22, weight: .light)); Text("值得记住的达成，会留在这里").font(.system(size: 12.5)) }.foregroundStyle(palette.muted)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.completedTasks) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark").font(.system(size: 11)).foregroundStyle(palette.muted).frame(width: 18, height: 22)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title).font(.system(size: 14)).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                                    if let done = item.completedAt { Text("达成于 " + DueDateFormatter.format(done, now: now)).font(.system(size: 10.5)).foregroundStyle(palette.muted) }
                                }
                                Spacer(minLength: 6)
                                Button { store.restore(item) } label: { Image(systemName: "arrow.uturn.backward").font(.system(size: 12)).foregroundStyle(palette.secondary).frame(width: 24, height: 24) }.buttonStyle(.plain).help("恢复目标").accessibilityLabel("恢复目标：" + item.title)
                            }.padding(.vertical, 14)
                            palette.line.frame(height: 0.5)
                        }
                    }.padding(.horizontal, 20)
                }.scrollIndicators(.hidden)
            }
        }
    }
}
