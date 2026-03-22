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

// MARK: - Intelligence pane

struct IntelligencePane: View {
    @AppStorage("autoImport.apiKey")       private var apiKey      = ""
    @AppStorage("autoImport.model")        private var model       = "qwen/qwen3-vl-235b-a22b-thinking"
    @AppStorage("autoImport.maxTokens")    private var maxTokens   = 1024
    @AppStorage("autoImport.showFreeOnly") private var showFreeOnly = false

    @AppStorage("autoImport.categorizationHintEnabled")      private var hintEnabled     = true
    @AppStorage("autoImport.categorizationHint")             private var storedHint      = ""
    @AppStorage("autoImport.categorizationHintExpenseCount") private var hintExpenseCount = 0
    @AppStorage("autoImport.categorizationHintLastUpdated")  private var hintLastUpdated: Double = 0

    @Environment(\.modelContext) private var modelContext

    @State private var availableModels: [OpenRouterModel] = []
    @State private var isFetching  = false
    @State private var fetchError: String? = nil
    @State private var isGeneratingHint = false
    @State private var hintError: String? = nil
    @State private var showHintPreview = false

    @State private var flowState: LearnerFlow = .idle
    @State private var suggestions: CategorySuggestions? = nil
    @State private var reassignments: [ReassignmentSuggestion] = []
    @State private var pendingExpenseCats: [String] = []
    @State private var pendingIncomeCats:  [String] = []
    @State private var showSuggestionsSheet   = false
    @State private var showReassignmentsSheet = false
    @State private var errorMessage: String?  = nil
    @State private var infoMessage:  String?  = nil

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

            Section {
                Toggle("Enable categorization hints", isOn: $hintEnabled)
                LabeledContent("Status") {
                    Text(hintStatusText)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Regenerate Now") {
                        Task { await regenerateHint() }
                    }
                    .disabled(apiKey.isEmpty || isGeneratingHint || !hintEnabled)
                    if isGeneratingHint {
                        ProgressView().controlSize(.small)
                    }
                }
                if !storedHint.isEmpty {
                    DisclosureGroup("Preview hint", isExpanded: $showHintPreview) {
                        Text(storedHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    }
                }
                if let err = hintError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Categorization Hint")
            } footer: {
                Text("A short summary of your expense patterns, generated from past data and injected into the AI prompt to improve category suggestions.")
            }

            Section {
                HStack {
                    Button("Suggest Improvements") {
                        Task { await runSuggestImprovements() }
                    }
                    .disabled(apiKey.isEmpty || flowState != .idle)
                    if flowState == .loadingSuggestions {
                        ProgressView().controlSize(.small)
                    }
                }
            } header: {
                Text("Category Improvement")
            } footer: {
                if apiKey.isEmpty {
                    Text("Configure your OpenRouter API key to use this feature.")
                } else {
                    Text("Analyses your records and suggests additions or removals to the category lists.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: apiKey) { await fetchModels() }
        .sheet(isPresented: $showSuggestionsSheet) {
            SuggestionsSheetView(
                suggestions: Binding(
                    get: { suggestions ?? CategorySuggestions(expenseDiffs: [], incomeDiffs: []) },
                    set: { suggestions = $0 }
                ),
                flowState: flowState,
                onApply: { Task { await applySelectedSuggestions() } },
                onCancel: {
                    showSuggestionsSheet = false
                    suggestions = nil
                    flowState = .idle
                }
            )
        }
        .sheet(isPresented: $showReassignmentsSheet) {
            ReassignmentsSheetView(
                reassignments: $reassignments,
                pendingExpenseCats: pendingExpenseCats,
                pendingIncomeCats: pendingIncomeCats,
                onApply: { Task { await applyFinal() } },
                onCancel: {
                    showReassignmentsSheet = false
                    reassignments = []
                    pendingExpenseCats = []
                    pendingIncomeCats = []
                }
            )
        }
        .alert("No Changes Suggested", isPresented: Binding(
            get: { infoMessage != nil },
            set: { if !$0 { infoMessage = nil } }
        )) {
            Button("OK") { infoMessage = nil }
        } message: {
            Text(infoMessage ?? "")
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

    private var hintStatusText: String {
        guard hintLastUpdated > 0 else { return "Not generated yet" }
        let date = Date(timeIntervalSince1970: hintLastUpdated)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Updated \(formatter.string(from: date)) · \(hintExpenseCount) expenses"
    }

    private func regenerateHint() async {
        guard !apiKey.isEmpty else { return }
        isGeneratingHint = true
        hintError = nil
        defer { isGeneratingHint = false }
        do {
            let allExpenses = try modelContext.fetch(FetchDescriptor<Expense>())
            guard allExpenses.count >= 5 else {
                hintError = "Need at least 5 expenses to generate a hint."
                return
            }
            let categories = loadCategories()
            let dataPoints = allExpenses
                .filter { !$0.itemName.isEmpty }
                .map { CategoryDataPoint(label: $0.itemName, category: $0.category) }
            let hint = try await generateCategorizationHint(
                expenses:   dataPoints,
                categories: categories,
                apiKey:     apiKey,
                model:      model,
                maxTokens:  maxTokens
            )
            storedHint = hint
            hintExpenseCount = allExpenses.count
            hintLastUpdated = Date().timeIntervalSince1970
        } catch {
            hintError = error.localizedDescription
        }
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

    // MARK: - Category Improvement

    private func runSuggestImprovements() async {
        let cats    = loadCategories()
        let incCats = loadIncomeCategories()
        flowState = .loadingSuggestions
        do {
            let allExpenses = try modelContext.fetch(FetchDescriptor<Expense>())
            let allIncomes  = try modelContext.fetch(FetchDescriptor<Income>())
            let expItems = allExpenses.map { CategoryDataPoint(label: $0.itemName, category: $0.category) }
            let incItems = allIncomes.map  { CategoryDataPoint(label: $0.source,   category: $0.category) }

            let result = try await suggestCategoryImprovements(
                expenseItems: expItems,
                incomeItems:  incItems,
                expenseCats:  cats,
                incomeCats:   incCats,
                apiKey:       apiKey,
                model:        model,
                maxTokens:    maxTokens
            )

            flowState = .idle
            if result.expenseDiffs.isEmpty && result.incomeDiffs.isEmpty {
                infoMessage = "Your categories already look good — no changes suggested."
            } else {
                suggestions = result
                showSuggestionsSheet = true
            }
        } catch {
            flowState = .idle
            errorMessage = error.localizedDescription
        }
    }

    private func applySelectedSuggestions() async {
        guard let sugg = suggestions else { return }

        let selectedExp = sugg.expenseDiffs.filter { $0.isSelected }
        let selectedInc = sugg.incomeDiffs.filter  { $0.isSelected }

        var newExpCats = loadCategories()
        for diff in selectedExp {
            switch diff.action {
            case .add:    if !newExpCats.contains(diff.name) { newExpCats.append(diff.name) }
            case .remove: newExpCats.removeAll { $0 == diff.name }
            }
        }
        var newIncCats = loadIncomeCategories()
        for diff in selectedInc {
            switch diff.action {
            case .add:    if !newIncCats.contains(diff.name) { newIncCats.append(diff.name) }
            case .remove: newIncCats.removeAll { $0 == diff.name }
            }
        }
        pendingExpenseCats = newExpCats
        pendingIncomeCats  = newIncCats

        let removedExpCats = selectedExp.filter { $0.action == .remove }.map { $0.name }
        let removedIncCats = selectedInc.filter { $0.action == .remove }.map { $0.name }

        if removedExpCats.isEmpty && removedIncCats.isEmpty {
            showSuggestionsSheet = false
            await applyFinal()
            return
        }

        flowState = .loadingReassignments
        do {
            let allExpenses = try modelContext.fetch(FetchDescriptor<Expense>())
            let allIncomes  = try modelContext.fetch(FetchDescriptor<Income>())

            let affectedExp = allExpenses
                .filter { removedExpCats.contains($0.category) }
                .map { (record: $0, label: $0.itemName.isEmpty ? "(unnamed)" : $0.itemName) }

            let affectedInc = allIncomes
                .filter { removedIncCats.contains($0.category) }
                .map { (record: $0, label: $0.source.isEmpty ? "(unnamed)" : $0.source) }

            let result = try await suggestReassignments(
                expenses:       affectedExp,
                incomes:        affectedInc,
                newExpenseCats: newExpCats,
                newIncomeCats:  newIncCats,
                apiKey:         apiKey,
                model:          model,
                maxTokens:      maxTokens
            )

            reassignments = result
            flowState = .idle
            showSuggestionsSheet = false
            showReassignmentsSheet = true
        } catch {
            flowState = .idle
            errorMessage = error.localizedDescription
        }
    }

    private func applyFinal() async {
        flowState = .applying
        do {
            for suggestion in reassignments {
                switch suggestion.ref {
                case .expense(let e): e.category = suggestion.suggestedCategory
                case .income(let i):  i.category = suggestion.suggestedCategory
                }
            }
            try modelContext.save()
            saveCategories(pendingExpenseCats.isEmpty ? loadCategories() : pendingExpenseCats)
            saveIncomeCategories(pendingIncomeCats.isEmpty ? loadIncomeCategories() : pendingIncomeCats)
        } catch {
            errorMessage = error.localizedDescription
        }
        flowState = .idle
        showSuggestionsSheet   = false
        showReassignmentsSheet = false
        reassignments      = []
        pendingExpenseCats = []
        pendingIncomeCats  = []
    }
}

// MARK: - Categories pane

private enum LearnerFlow: Equatable {
    case idle, loadingSuggestions, loadingReassignments, applying
}

struct CategoriesPane: View {
    @State private var categories: [String] = []
    @State private var newCategoryText = ""
    @State private var incomeCategories: [String] = []
    @State private var newIncomeCategoryText = ""
    @State private var expenseDragItem: String? = nil
    @State private var expenseDragOffset: CGFloat = 0
    @State private var incomeDragItem: String? = nil
    @State private var incomeDragOffset: CGFloat = 0

    var body: some View {
        Form {
            Section("Expense Categories") {
                ForEach(categories, id: \.self) { cat in
                    categoryRow(cat, in: $categories,
                                dragItem: $expenseDragItem,
                                dragOffset: $expenseDragOffset,
                                save: saveCategories)
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

            Section("Income Categories") {
                ForEach(incomeCategories, id: \.self) { cat in
                    categoryRow(cat, in: $incomeCategories,
                                dragItem: $incomeDragItem,
                                dragOffset: $incomeDragOffset,
                                save: saveIncomeCategories)
                }
                HStack {
                    TextField("New category", text: $newIncomeCategoryText)
                    Button("Add") {
                        let trimmed = newIncomeCategoryText.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !incomeCategories.contains(trimmed) else { return }
                        incomeCategories.append(trimmed)
                        saveIncomeCategories(incomeCategories)
                        newIncomeCategoryText = ""
                    }
                    .disabled(newIncomeCategoryText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Restore Defaults") {
                    incomeCategories = defaultIncomeCategories
                    saveIncomeCategories(incomeCategories)
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            categories = loadCategories()
            incomeCategories = loadIncomeCategories()
        }
    }

    private func computeShift(for cat: String, in list: [String],
                              dragItem: String?, dragOffset: CGFloat,
                              rowHeight: CGFloat) -> CGFloat {
        guard let df = dragItem.flatMap({ list.firstIndex(of: $0) }),
              let fromIdx = list.firstIndex(of: cat),
              dragItem != cat else { return 0 }
        let moved = Int((dragOffset / rowHeight).rounded())
        let targetIdx = max(0, min(list.count - 1, df + moved))
        if df < fromIdx && fromIdx <= targetIdx { return -rowHeight }
        if df > fromIdx && fromIdx >= targetIdx { return rowHeight }
        return 0
    }

    @ViewBuilder
    private func categoryRow(
        _ cat: String,
        in list: Binding<[String]>,
        dragItem: Binding<String?>,
        dragOffset: Binding<CGFloat>,
        save: @escaping ([String]) -> Void
    ) -> some View {
        let rowHeight: CGFloat = 36
        let isDragging = dragItem.wrappedValue == cat
        let shiftY = computeShift(for: cat, in: list.wrappedValue,
                                  dragItem: dragItem.wrappedValue,
                                  dragOffset: dragOffset.wrappedValue,
                                  rowHeight: rowHeight)

        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .imageScale(.small)
                .frame(width: 20)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if dragItem.wrappedValue == nil { dragItem.wrappedValue = cat }
                            dragOffset.wrappedValue = value.translation.height
                        }
                        .onEnded { _ in
                            guard let dragged = dragItem.wrappedValue,
                                  let from = list.wrappedValue.firstIndex(of: dragged) else {
                                dragItem.wrappedValue = nil
                                dragOffset.wrappedValue = 0
                                return
                            }
                            let moved = Int((dragOffset.wrappedValue / rowHeight).rounded())
                            let to = max(0, min(list.wrappedValue.count - 1, from + moved))
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if from != to {
                                    list.wrappedValue.move(fromOffsets: IndexSet(integer: from),
                                                           toOffset: to > from ? to + 1 : to)
                                    save(list.wrappedValue)
                                }
                                dragItem.wrappedValue = nil
                                dragOffset.wrappedValue = 0
                            }
                        }
                )
            Text(cat)
            Spacer()
            Button {
                list.wrappedValue.removeAll { $0 == cat }
                save(list.wrappedValue)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .offset(y: isDragging ? dragOffset.wrappedValue : shiftY)
        .animation(.spring(response: 0.2, dampingFraction: 0.9), value: shiftY)
        .zIndex(isDragging ? 1 : 0)
        .scaleEffect(isDragging ? 1.02 : 1, anchor: .center)
        .shadow(color: .black.opacity(isDragging ? 0.15 : 0), radius: isDragging ? 4 : 0)
    }
}

// MARK: - Suggestions sheet

private struct SuggestionsSheetView: View {
    @Binding var suggestions: CategorySuggestions
    let flowState: LearnerFlow
    let onApply:  () -> Void
    let onCancel: () -> Void

    private var selectedCount: Int {
        suggestions.expenseDiffs.filter { $0.isSelected }.count +
        suggestions.incomeDiffs.filter  { $0.isSelected }.count
    }

    var body: some View {
        NavigationStack {
            List {
                if !suggestions.expenseDiffs.isEmpty {
                    Section("Expense Categories") {
                        ForEach($suggestions.expenseDiffs) { $diff in
                            DiffRowView(diff: $diff)
                        }
                    }
                }
                if !suggestions.incomeDiffs.isEmpty {
                    Section("Income Categories") {
                        ForEach($suggestions.incomeDiffs) { $diff in
                            DiffRowView(diff: $diff)
                        }
                    }
                }
            }
            .navigationTitle("Suggested Category Changes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(flowState == .loadingReassignments)
                }
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 8) {
                        if flowState == .loadingReassignments {
                            ProgressView().controlSize(.small)
                        }
                        Button("Apply Selected", action: onApply)
                            .disabled(selectedCount == 0 || flowState == .loadingReassignments)
                    }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 340)
    }
}

private struct DiffRowView: View {
    @Binding var diff: CategoryDiff

    var body: some View {
        Toggle(isOn: $diff.isSelected) {
            HStack(alignment: .top, spacing: 8) {
                Text(diff.action == .add ? "+" : "−")
                    .font(.system(.body, design: .monospaced).bold())
                    .foregroundStyle(diff.action == .add ? Color.green : Color.red)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(diff.name)
                    Text(diff.reasoning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Reassignments sheet

private struct ReassignmentsSheetView: View {
    @Binding var reassignments: [ReassignmentSuggestion]
    let pendingExpenseCats: [String]
    let pendingIncomeCats:  [String]
    let onApply:  () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($reassignments) { $suggestion in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(suggestion.recordLabel)
                                .fontWeight(.medium)
                            HStack {
                                Text(suggestion.currentCategory)
                                    .foregroundStyle(.secondary)
                                    .strikethrough()
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Picker("", selection: $suggestion.suggestedCategory) {
                                    ForEach(categoriesFor(suggestion), id: \.self) { cat in
                                        Text(cat).tag(cat)
                                    }
                                }
                                .labelsHidden()
                                .fixedSize()
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } footer: {
                    Text("\(reassignments.count) record(s) will be reassigned.")
                }
            }
            .navigationTitle("Reassign Records")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: onApply)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 340)
    }

    private func categoriesFor(_ suggestion: ReassignmentSuggestion) -> [String] {
        switch suggestion.ref {
        case .expense: return pendingExpenseCats
        case .income:  return pendingIncomeCats
        }
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
                Text("Saves all data, documents, and settings. Includes the API key.")
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
                Text("Restores from a .akaunbackup file. The app will restart automatically.")
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
                Text("Restores AI configuration and expense categories to their defaults. Your data is not affected.")
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
            Text("This will restore the API key, model, max tokens, and expense and income categories to their defaults. This cannot be undone.")
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
        saveIncomeCategories(defaultIncomeCategories)
        UserDefaults.standard.removeObject(forKey: "autoImport.categorizationHint")
        UserDefaults.standard.removeObject(forKey: "autoImport.categorizationHintExpenseCount")
        UserDefaults.standard.removeObject(forKey: "autoImport.categorizationHintEnabled")
        UserDefaults.standard.removeObject(forKey: "autoImport.categorizationHintLastUpdated")
        UserDefaults.standard.set(false, forKey: "godMode.enabled")
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

// MARK: - Advanced Pane

struct AdvancedPane: View {
    @AppStorage("godMode.enabled") private var godModeEnabled = false

    var body: some View {
        Form {
            Section {
                Toggle("God Mode", isOn: $godModeEnabled)
                Text("When enabled, editing an expense that is part of a claim will unlock all descriptive fields (item name, supplier, date, reference, remark, attachments). The amount remains locked because it affects the claim total.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Editing")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Advanced")
        .frame(minWidth: 480, minHeight: 200)
    }
}
