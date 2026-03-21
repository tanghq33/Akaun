import AppKit
import Quartz
import QuickLookUI
import SwiftUI
import SwiftData

// MARK: - QuickLook Preview Support

final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var previewURLs: [URL] = []

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURLs[index] as NSURL
    }

    func show(urls: [URL], at index: Int) {
        previewURLs = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = index
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }
}

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

struct AttachmentListView: View {
    private let storedItems: [(filename: String, displayName: String)]
    var legacyFilename: String? = nil

    @State private var quickLookCoordinator = QuickLookCoordinator()

    init(attachments: [Attachment], legacyFilename: String? = nil) {
        self.storedItems = attachments.map { ($0.filename, $0.displayName) }
        self.legacyFilename = legacyFilename
    }

    init(claimAttachments: [ClaimAttachment]) {
        self.storedItems = claimAttachments.map { ($0.filename, $0.displayName) }
    }

    var body: some View {
        let items: [(String, String)] = {
            if !storedItems.isEmpty {
                return storedItems.map { ($0.filename, $0.displayName) }
            } else if let legacy = legacyFilename {
                return [(legacy, DocumentStore.displayName(for: legacy))]
            }
            return []
        }()

        if !items.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(items.count == 1 ? "Attachment" : "Attachments (\(items.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(items.enumerated()), id: \.element.0) { index, item in
                    Button {
                        let urls = items.map { DocumentStore.url(for: $0.0) }
                        quickLookCoordinator.show(urls: urls, at: index)
                    } label: {
                        Label(item.1, systemImage: "paperclip")
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
}
