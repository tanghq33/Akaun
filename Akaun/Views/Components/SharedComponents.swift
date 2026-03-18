import AppKit
import SwiftUI

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct WideDatePicker: NSViewRepresentable {
    @Binding var selection: Date

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .yearMonthDay
        picker.dateValue = selection
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        picker.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        picker.dateValue = selection
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    final class Coordinator {
        var selection: Binding<Date>
        init(selection: Binding<Date>) { self.selection = selection }
        @objc func dateChanged(_ sender: NSDatePicker) {
            selection.wrappedValue = sender.dateValue
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }
}
