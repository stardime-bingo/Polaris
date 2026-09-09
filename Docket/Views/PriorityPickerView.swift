import SwiftUI

struct PriorityPickerView: View {
    @Binding var priority: Priority
    @Environment(\.polarisPalette) private var palette
    var body: some View {
        HStack(spacing: 12) {
            Text("优先级").font(.system(size: 12.5)).foregroundStyle(palette.secondary).frame(width: 52, alignment: .leading)
            Spacer(minLength: 0)
            Picker("优先级", selection: $priority) {
                ForEach(Priority.allCases) { Text($0.displayName).tag($0) }
            }.labelsHidden().pickerStyle(.segmented).controlSize(.small)
        }.frame(minHeight: 36)
    }
}
