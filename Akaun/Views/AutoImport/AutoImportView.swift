import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AutoImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AutoImportQueue.self) private var queue

    @AppStorage("autoImport.apiKey") private var apiKey = ""
    @AppStorage("autoImport.model") private var model = "google/gemini-2.5-flash"
    @AppStorage("autoImport.maxTokens") private var maxTokens = 1024

    @State private var isDragTargeted = false
    @State private var showingFilePicker = false

    var body: some View {
        Group {
            if queue.processingItems.isEmpty {
                emptyDropZone
            } else {
                ZStack {
                    List {
                        Section {
                            compactDropZone
                        }
                        ForEach(queue.processingItems) { item in
                            AutoImportQueueRowView(item: item) {
                                queue.retryItem(item, apiKey: apiKey, model: model, maxTokens: maxTokens, expenseCategories: loadCategories(), incomeCategories: loadIncomeCategories())
                            } onRemove: {
                                queue.removeItem(item)
                            } onStop: {
                                queue.stopItem(item)
                            }
                        }
                    }
                    .listStyle(.plain)

                    if isDragTargeted {
                        dropOverlay
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                    Task { await handleDrop(providers: providers) }
                    return true
                }
            }
        }
        .navigationTitle("Auto Import")
        .toolbar {
            ToolbarItemGroup {
                if queue.items.contains(where: { $0.state == .extracting || $0.state == .calling }) {
                    Button("Stop All") { queue.stopAll() }
                }
                if queue.items.contains(where: { if case .failed = $0.state { return true }; return false }) {
                    Button("Retry All") {
                        queue.retryAllFailed(
                            apiKey: apiKey, model: model, maxTokens: maxTokens,
                            expenseCategories: loadCategories(), incomeCategories: loadIncomeCategories()
                        )
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf, .png, .jpeg],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                let filtered = urls.filter { isSupportedFile($0) }
                queue.enqueue(filtered, apiKey: apiKey, model: model, maxTokens: maxTokens, expenseCategories: loadCategories(), incomeCategories: loadIncomeCategories())
            }
        }
    }

    // MARK: - Drop Zones

    private var emptyDropZone: some View {
        VStack {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isDragTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 2, dash: [8])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isDragTargeted ? Color.accentColor.opacity(0.06) : Color.clear)
                    )
                VStack(spacing: 12) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 48))
                        .foregroundStyle(isDragTargeted ? Color.accentColor : Color.secondary)
                    Text("Drop receipts & invoices here")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("PDF, PNG, JPG — multiple files supported")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Browse…") { showingFilePicker = true }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                }
                .padding(40)
            }
            .frame(maxWidth: 480, maxHeight: 300)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            Task { await handleDrop(providers: providers) }
            return true
        }
    }

    private var compactDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDragTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isDragTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
                )
            HStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .foregroundStyle(isDragTargeted ? Color.accentColor : Color.secondary)
                Text("Drop more files…")
                    .font(.subheadline)
                    .foregroundStyle(isDragTargeted ? Color.accentColor : Color.secondary)
                Spacer()
                Button("Browse…") { showingFilePicker = true }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 40)
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 4, trailing: 8))
        .listRowSeparator(.hidden)
    }

    private var dropOverlay: some View {
        ZStack {
            Color.accentColor.opacity(0.08)
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                .padding(8)
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
                Text("Drop files to add to queue")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    private func handleDrop(providers: [NSItemProvider]) async {
        var urls: [URL] = []
        for provider in providers {
            if let url = await loadURL(from: provider), isSupportedFile(url) {
                urls.append(url)
            }
        }
        if !urls.isEmpty {
            queue.enqueue(urls, apiKey: apiKey, model: model, maxTokens: maxTokens, expenseCategories: loadCategories(), incomeCategories: loadIncomeCategories())
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func isSupportedFile(_ url: URL) -> Bool {
        ["pdf", "png", "jpg", "jpeg"].contains(url.pathExtension.lowercased())
    }
}
