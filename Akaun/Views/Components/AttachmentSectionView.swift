import Quartz
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

struct AttachmentItem: Identifiable {
    let id = UUID()
    var filename: String
    var displayName: String
}

private struct AttachmentRowView: View {
    let item: AttachmentItem
    let index: Int
    let allAttachments: [AttachmentItem]
    let quickLookCoordinator: QuickLookCoordinator
    let onRemove: (AttachmentItem) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack {
            Button {
                showPreview()
            } label: {
                Label(item.displayName, systemImage: "paperclip")
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                showPreview()
            } label: {
                Image(systemName: "doc.viewfinder")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(isHovering ? 1 : 0)
            Button("Remove", role: .destructive) {
                onRemove(item)
            }
            .buttonStyle(.borderless)
        }
        .onHover { isHovering = $0 }
    }

    private func showPreview() {
        let urls = allAttachments.map { DocumentStore.url(for: $0.filename) }
        quickLookCoordinator.show(urls: urls, at: index)
    }
}

struct AttachmentSectionView: View {
    let subfolder: String
    @Binding var attachments: [AttachmentItem]
    /// Filenames that existed before this editing session — only these get deleted from disk on remove.
    let existingFilenames: Set<String>
    /// Tracks filenames added during this session for cleanup on cancel.
    @Binding var newFilenames: Set<String>

    @State private var quickLookCoordinator = QuickLookCoordinator()
    @State private var showingFilePicker = false
    @State private var fileImportError: String?
    @State private var isDragTargeted = false

    var body: some View {
        Section("Attachments") {
            ForEach(Array(attachments.enumerated()), id: \.element.id) { index, item in
                AttachmentRowView(
                    item: item,
                    index: index,
                    allAttachments: attachments,
                    quickLookCoordinator: quickLookCoordinator,
                    onRemove: removeAttachment
                )
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isDragTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isDragTargeted ? Color.accentColor.opacity(0.06) : Color.clear)
                    )
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.title2)
                        .foregroundStyle(isDragTargeted ? Color.accentColor : Color.secondary)
                    Text("Drop files here")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Button("Browse…") { showingFilePicker = true }
                        .buttonStyle(.borderless)
                }
                .padding(.vertical, 16)
            }
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                for provider in providers {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                        guard let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                        DispatchQueue.main.async { attachURL(url) }
                    }
                }
                return true
            }

            if let error = fileImportError {
                Text(error).foregroundStyle(.red).font(.caption)
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls { attachURL(url) }
            case .failure(let error):
                fileImportError = error.localizedDescription
            }
        }
    }

    private func attachURL(_ url: URL) {
        do {
            let filename = try DocumentStore.importFile(from: url, subfolder: subfolder)
            let display = DocumentStore.displayName(for: filename)
            attachments.append(AttachmentItem(filename: filename, displayName: display))
            newFilenames.insert(filename)
            fileImportError = nil
        } catch {
            fileImportError = "Could not attach file: \(error.localizedDescription)"
        }
    }

    private func removeAttachment(_ item: AttachmentItem) {
        if existingFilenames.contains(item.filename) {
            // Existing attachment — delete from disk now
            DocumentStore.deleteFile(named: item.filename)
        } else {
            // Newly added — just remove from tracking; file already on disk will be cleaned on cancel if not saved
            newFilenames.remove(item.filename)
            DocumentStore.deleteFile(named: item.filename)
        }
        attachments.removeAll { $0.id == item.id }
    }
}
