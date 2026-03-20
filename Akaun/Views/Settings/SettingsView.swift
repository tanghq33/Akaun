import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

// MARK: - OpenRouter types

private struct OpenRouterModel: Decodable, Identifiable {
    let id: String
    let name: String
    let pricing: Pricing?
    let canonical_slug: String?

    struct Pricing: Decodable {
        let prompt: String?
    }

    var isFree: Bool {
        guard let p = pricing?.prompt else { return false }
        return (Double(p) ?? 1) == 0
    }

    var slug: String { canonical_slug ?? id }
}

private struct OpenRouterModelsResponse: Decodable {
    let data: [OpenRouterModel]
}

// MARK: - Panes (used by SettingsWindowController)

// MARK: - Auto Import pane

struct AutoImportPane: View {
    @AppStorage("autoImport.apiKey")       private var apiKey      = ""
    @AppStorage("autoImport.model")        private var model       = "qwen/qwen3-vl-235b-a22b-thinking"
    @AppStorage("autoImport.maxTokens")    private var maxTokens   = 1024
    @AppStorage("autoImport.showFreeOnly") private var showFreeOnly = false

    @State private var availableModels: [OpenRouterModel] = []
    @State private var isFetching  = false
    @State private var fetchError: String? = nil

    private var filteredModels: [OpenRouterModel] {
        guard showFreeOnly else { return availableModels }
        let free = availableModels.filter { $0.isFree }
        if !free.contains(where: { $0.slug == model }),
           let current = availableModels.first(where: { $0.slug == model }) {
            return [current] + free
        }
        return free
    }

    var body: some View {
        Form {
            Section("OpenRouter") {
                SecureField("API Key", text: $apiKey)
                modelPickerRow
                Toggle("Free models only", isOn: $showFreeOnly)
                    .disabled(availableModels.isEmpty)
                TextField("Max Tokens", value: $maxTokens, format: .number)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: apiKey) { await fetchModels() }
    }

    @ViewBuilder
    private var modelPickerRow: some View {
        HStack {
            if availableModels.isEmpty && !isFetching {
                Picker("Model", selection: $model) {
                    Text(model).tag(model)
                }
                Text("Enter API key and refresh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isFetching {
                Picker("Model", selection: $model) {
                    Text(model).tag(model)
                }
                ProgressView().controlSize(.small)
            } else {
                Picker("Model", selection: $model) {
                    ForEach(filteredModels) { m in
                        Text(m.name).tag(m.slug)
                    }
                }
            }
            Button {
                Task { await fetchModels() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(isFetching || apiKey.isEmpty)
        }
        if let error = fetchError {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    private func fetchModels() async {
        guard !apiKey.isEmpty else { return }
        isFetching = true
        fetchError = nil
        defer { isFetching = false }
        do {
            var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)
            var response = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
            response = OpenRouterModelsResponse(data: response.data.sorted { $0.name < $1.name })
            availableModels = response.data
        } catch {
            fetchError = error.localizedDescription
        }
    }
}

// MARK: - Categories pane

struct CategoriesPane: View {
    @State private var categories: [String] = []
    @State private var newCategoryText = ""

    var body: some View {
        Form {
            Section("Categories") {
                ForEach(categories, id: \.self) { cat in
                    HStack {
                        Text(cat)
                        Spacer()
                        Button {
                            categories.removeAll { $0 == cat }
                            saveCategories(categories)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("New category", text: $newCategoryText)
                    Button("Add") {
                        let trimmed = newCategoryText.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !categories.contains(trimmed) else { return }
                        categories.append(trimmed)
                        saveCategories(categories)
                        newCategoryText = ""
                    }
                    .disabled(newCategoryText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Restore Defaults") {
                    categories = defaultCategories
                    saveCategories(categories)
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { categories = loadCategories() }
    }
}

// MARK: - Backup pane

struct BackupPane: View {
    let modelContainer: ModelContainer

    @AppStorage("backup.lastBackupDate") private var lastBackupDateInterval: Double = 0
    @State private var isBackingUp = false
    @State private var isRestoring = false
    @State private var errorMessage: String? = nil
    @State private var showRestoreConfirmation = false
    @State private var pendingRestoreURL: URL? = nil

    private var lastBackupText: String {
        guard lastBackupDateInterval > 0 else { return "Never" }
        let date = Date(timeIntervalSince1970: lastBackupDateInterval)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Last Backup") {
                    Text(lastBackupText)
                        .foregroundStyle(.secondary)
                }
                Button("Create Backup…") {
                    Task { await createBackup() }
                }
                .disabled(isBackingUp || isRestoring)
            } header: {
                Text("Backup")
            } footer: {
                Text("Saves all data, documents, and settings. The API key is not included.")
            }

            Section {
                Button("Restore from Backup…") {
                    Task { await pickRestoreFile() }
                }
                .foregroundStyle(.red)
                .disabled(isBackingUp || isRestoring)
            } header: {
                Text("Restore")
            } footer: {
                Text("Restores from a .akaunbackup file. The app will restart automatically. The API key is not affected.")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .confirmationDialog(
            "Restore from Backup?",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore and Restart", role: .destructive) {
                Task { await confirmRestore() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All current data will be replaced with the contents of the backup. The app will restart to apply the restore. This cannot be undone.")
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func createBackup() async {
        isBackingUp = true
        defer { isBackingUp = false }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(exportedAs: "com.quanlab.akaun.backup")]
        panel.canCreateDirectories = true
        let dateStr = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date.now)
        }()
        panel.nameFieldStringValue = "Akaun Backup \(dateStr)"

        guard let window = NSApp.keyWindow else { return }
        let response = await panel.beginSheetModal(for: window)
        guard response == .OK, let url = panel.url else { return }

        do {
            try await Task.detached(priority: .userInitiated) {
                try BackupService.createBackup(to: url, modelContainer: modelContainer)
            }.value
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pickRestoreFile() async {
        isRestoring = true
        defer { isRestoring = false }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(exportedAs: "com.quanlab.akaun.backup")]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard let window = NSApp.keyWindow else { return }
        let response = await panel.beginSheetModal(for: window)
        guard response == .OK, let url = panel.url else { return }

        pendingRestoreURL = url
        showRestoreConfirmation = true
    }

    private func confirmRestore() async {
        guard let url = pendingRestoreURL else { return }
        do {
            try BackupService.stageRestore(from: url)
            BackupService.restartApp()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Reset pane

struct ResetPane: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("autoImport.apiKey")       private var apiKey      = ""
    @AppStorage("autoImport.model")        private var model       = "qwen/qwen3-vl-235b-a22b-thinking"
    @AppStorage("autoImport.maxTokens")    private var maxTokens   = 1024
    @AppStorage("autoImport.showFreeOnly") private var showFreeOnly = false

    @State private var showResetSettingsConfirmation = false
    @State private var showResetDataConfirmation = false
    @State private var showResetEverythingConfirmation = false

    var body: some View {
        Form {
            Section {
                Button("Reset Settings…") {
                    showResetSettingsConfirmation = true
                }
                .foregroundStyle(.red)
            } footer: {
                Text("Restores Auto Import configuration and expense categories to their defaults. Your data is not affected.")
            }

            Section {
                Button("Reset Data…") {
                    showResetDataConfirmation = true
                }
                .foregroundStyle(.red)
            } footer: {
                Text("Deletes all expenses, payments, claims, running numbers, and imported documents. Your settings are not affected.")
            }

            Section {
                Button("Reset Everything…") {
                    showResetEverythingConfirmation = true
                }
                .foregroundStyle(.red)
            } footer: {
                Text("Deletes all data and restores all settings to their defaults.")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .confirmationDialog(
            "Reset Settings?",
            isPresented: $showResetSettingsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Settings", role: .destructive) { resetSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore the API key, model, max tokens, and expense categories to their defaults. This cannot be undone.")
        }
        .confirmationDialog(
            "Reset Data?",
            isPresented: $showResetDataConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Data", role: .destructive) { resetData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all expenses, payments, claims, running numbers, and imported documents. This cannot be undone.")
        }
        .confirmationDialog(
            "Reset Everything?",
            isPresented: $showResetEverythingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Everything", role: .destructive) { resetEverything() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all data and restore all settings to their defaults. This cannot be undone.")
        }
    }

    private func resetSettings() {
        apiKey       = ""
        model        = "qwen/qwen3-vl-235b-a22b-thinking"
        maxTokens    = 1024
        showFreeOnly = false
        saveCategories(defaultCategories)
    }

    private func resetData() {
        try? modelContext.delete(model: Expense.self)
        try? modelContext.delete(model: Income.self)
        try? modelContext.delete(model: Claim.self)
        try? modelContext.delete(model: AppSequence.self)
        DocumentStore.removeAllDocuments()
    }

    private func resetEverything() {
        resetSettings()
        resetData()
    }
}
