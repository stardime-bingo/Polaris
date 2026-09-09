import SwiftUI

struct ReminderPickerView: View {
    @Binding var offset: ReminderOffset
    @Environment(\.polarisPalette) private var palette
    var body: some View {
        HStack(spacing: 12) {
            Text("提醒").font(.system(size: 12.5)).foregroundStyle(palette.secondary).frame(width: 52, alignment: .leading)
            Picker("提醒时间", selection: $offset) {
                ForEach(ReminderOffset.allCases) { value in Text(value.displayName).tag(value) }
            }.labelsHidden().pickerStyle(.menu).controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .trailing).accessibilityLabel("提醒时间")
        }
    }
}
