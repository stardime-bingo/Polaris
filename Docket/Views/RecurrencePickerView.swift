import SwiftUI

struct RecurrencePickerView: View {
    @Binding var hasRecurrence: Bool
    @Binding var frequency: Frequency
    @Binding var interval: Int
    @Environment(\.polarisPalette) private var palette
    private var selection: Binding<Frequency?> {
        Binding(get: { hasRecurrence ? frequency : nil }, set: { value in
            if let value { hasRecurrence = true; frequency = value }
            else { hasRecurrence = false }
        })
    }
    var body: some View {
        HStack(spacing: 12) {
            Text("重复").font(.system(size: 12.5)).foregroundStyle(palette.secondary).frame(width: 52, alignment: .leading)
            Picker("重复周期", selection: selection) {
                Text("不重复").tag(nil as Frequency?)
                ForEach(Frequency.allCases) { value in Text(value.displayName).tag(Optional(value)) }
            }.labelsHidden().pickerStyle(.menu).controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .trailing).accessibilityLabel("重复周期")
            if hasRecurrence {
                Stepper(value: $interval, in: 1...99) {
                    Text("每 \(interval) \(frequency.unit)").font(.system(size: 11.5)).monospacedDigit()
                }.controlSize(.small).frame(width: 110)
                    .foregroundStyle(palette.secondary).accessibilityLabel("重复间隔")
            }
        }
    }
}
