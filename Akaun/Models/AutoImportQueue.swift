import Foundation
import SwiftData

// MARK: - State

enum QueueItemState: Equatable {
    case extracting
    case calling
    case ready
    case imported
    case failed(String)
}

// MARK: - Queue Item

@Observable
final class AutoImportQueueItem: Identifiable {
    let id = UUID()
    let sourceFile: URL
    var state: QueueItemState = .extracting
    var documentType: DocumentType = .expense
    var itemName: String = ""
    var supplier: String = ""
    var date: Date = .now
    var amountCents: Int = 0
    var reference: String = ""
    var status: ExpenseStatus = .unpaid
    var category: String = "Other"
    @ObservationIgnored var isStopped: Bool = false
    /// nil = not yet checked. [] = checked, no duplicates. Non-empty = has conflicts.
    var duplicateMatches: [DuplicateMatch]? = nil
    /// True when user chose "Skip" in the auto-detection sheet.
    var isSkipped: Bool = false

    init(sourceFile: URL) {
        self.sourceFile = sourceFile
    }
}

// MARK: - Processing Controller

private actor ProcessingController {
    private var activeCount = 0
    private var maxConcurrent: Int
    private var rateLimitDelay: TimeInterval
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var lastAcquireTime: Date = .distantPast

    init(maxConcurrent: Int, rateLimitDelay: TimeInterval) {
        self.maxConcurrent = maxConcurrent
        self.rateLimitDelay = rateLimitDelay
    }

    func updateSettings(maxConcurrent: Int, rateLimitDelay: TimeInterval) {
        self.maxConcurrent = maxConcurrent
        self.rateLimitDelay = rateLimitDelay
    }

    /// Returns nanoseconds to sleep before starting work.
    func acquire() async -> UInt64 {
        while activeCount >= maxConcurrent {
            await withCheckedContinuation { waiters.append($0) }
        }
        let elapsed = Date().timeIntervalSince(lastAcquireTime)
        let wait = max(0, rateLimitDelay - elapsed)
        activeCount += 1
        lastAcquireTime = Date().addingTimeInterval(wait)
        return UInt64(wait * 1_000_000_000)
    }

    func release() {
        activeCount -= 1
        if let w = waiters.first { waiters.removeFirst(); w.resume() }
    }
}

// MARK: - Queue

@Observable
final class AutoImportQueue {
    var items: [AutoImportQueueItem] = []
    private var controller = ProcessingController(maxConcurrent: 1, rateLimitDelay: 0)

    var processingItems: [AutoImportQueueItem] {
        items.filter { item in
            switch item.state {
            case .extracting, .calling, .failed: return true
            default: return false
            }
        }
    }

    var reviewItems: [AutoImportQueueItem] {
        items.filter { $0.state == .ready || $0.state == .imported }
    }

    func removeItem(_ item: AutoImportQueueItem) {
        item.isStopped = true
        items.removeAll { $0.id == item.id }
    }

    func stopItem(_ item: AutoImportQueueItem) {
        item.isStopped = true
        item.state = .failed("Stopped")
    }

    func stopAll() {
        for item in items where item.state == .extracting || item.state == .calling {
            stopItem(item)
        }
    }

    func retryAllFailed(
        apiKey: String,
        model: String,
        maxTokens: Int,
        expenseCategories: [String] = [],
        incomeCategories: [String] = []
    ) {
        let failed = items.filter { if case .failed = $0.state { return true }; return false }
        for item in failed {
            retryItem(item, apiKey: apiKey, model: model, maxTokens: maxTokens,
                      expenseCategories: expenseCategories, incomeCategories: incomeCategories)
        }
    }

    func enqueue(
        _ urls: [URL],
        apiKey: String,
        model: String,
        maxTokens: Int,
        expenseCategories: [String] = [],
        incomeCategories: [String] = []
    ) {
        let hint = currentHint

        let parallelTasks = UserDefaults.standard.object(forKey: "autoImport.parallelTasks").flatMap { $0 as? Int } ?? 1
        let rateLimitDelay = UserDefaults.standard.object(forKey: "autoImport.rateLimitDelay").flatMap { $0 as? Double } ?? 0.0
        Task { await controller.updateSettings(maxConcurrent: max(1, parallelTasks), rateLimitDelay: max(0, rateLimitDelay)) }

        for url in urls {
            let item = AutoImportQueueItem(sourceFile: url)
            items.append(item)
            Task {
                let sleepNs = await controller.acquire()
                guard !item.isStopped else { await controller.release(); return }
                if sleepNs > 0 { try? await Task.sleep(nanoseconds: sleepNs) }
                guard !item.isStopped else { await controller.release(); return }
                let result = await processSingleFile(
                    url: url,
                    apiKey: apiKey,
                    model: model,
                    maxTokens: maxTokens,
                    expenseCategories: expenseCategories,
                    incomeCategories: incomeCategories,
                    hint: hint,
                    onStateChange: { newState in
                        guard !item.isStopped else { return }
                        item.state = newState
                    }
                )
                await controller.release()
                guard !item.isStopped else { return }
                apply(result, to: item)
            }
        }
    }

    func retryItem(
        _ item: AutoImportQueueItem,
        apiKey: String,
        model: String,
        maxTokens: Int,
        expenseCategories: [String] = [],
        incomeCategories: [String] = []
    ) {
        let hint = currentHint

        item.isStopped = false
        item.state = .extracting
        item.documentType = .expense
        item.itemName = ""
        item.supplier = ""
        item.category = "Other"
        item.duplicateMatches = nil
        item.isSkipped = false
        Task {
            let sleepNs = await controller.acquire()
            guard !item.isStopped else { await controller.release(); return }
            if sleepNs > 0 { try? await Task.sleep(nanoseconds: sleepNs) }
            guard !item.isStopped else { await controller.release(); return }
            let result = await processSingleFile(
                url: item.sourceFile,
                apiKey: apiKey,
                model: model,
                maxTokens: maxTokens,
                expenseCategories: expenseCategories,
                incomeCategories: incomeCategories,
                hint: hint,
                onStateChange: { newState in
                    guard !item.isStopped else { return }
                    item.state = newState
                }
            )
            await controller.release()
            guard !item.isStopped else { return }
            apply(result, to: item)
        }
    }

    func importItem(_ item: AutoImportQueueItem, in context: ModelContext) {
        do {
            switch item.documentType {
            case .expense:
                let filename = try DocumentStore.importFile(from: item.sourceFile, subfolder: "Expenses")
                let displayName = DocumentStore.displayName(for: filename)
                let expense = Expense(
                    expenseNumber: RunningNumberGenerator.next(prefix: "EX", for: item.date, in: context),
                    itemName: item.itemName,
                    supplier: item.supplier,
                    date: item.date,
                    amountCents: item.amountCents,
                    reference: item.reference,
                    status: item.status,
                    category: item.category
                )
                context.insert(expense)
                let attachment = Attachment(filename: filename, displayName: displayName, addedDate: item.date)
                expense.attachments.append(attachment)
                try context.save()
                Task { await extractAndStoreSearchText(for: expense, in: context) }

            case .income:
                let filename = try DocumentStore.importFile(from: item.sourceFile, subfolder: "Income")
                let displayName = DocumentStore.displayName(for: filename)
                let income = Income(
                    incomeNumber: RunningNumberGenerator.next(prefix: "IN", for: item.date, in: context),
                    source: item.supplier,
                    descriptionText: item.itemName,
                    date: item.date,
                    amountCents: item.amountCents,
                    reference: item.reference,
                    category: item.category
                )
                context.insert(income)
                let attachment = IncomeAttachment(filename: filename, displayName: displayName, addedDate: item.date)
                income.attachments.append(attachment)
                try context.save()
                Task { await extractAndStoreSearchText(for: income, in: context) }
            }

            item.state = .imported
        } catch {
            item.state = .failed(error.localizedDescription)
        }
    }

    func importAllReady(in context: ModelContext) {
        for item in items where item.state == .ready && !item.isSkipped && (item.duplicateMatches ?? []).isEmpty {
            importItem(item, in: context)
        }
    }

    func clearCompleted() {
        items.removeAll { $0.state == .imported }
    }

    // MARK: - Categorization hint

    func startupHintCheckIfNeeded(in context: ModelContext) async {
        let apiKey = UserDefaults.standard.string(forKey: "autoImport.apiKey") ?? ""
        guard !apiKey.isEmpty else { return }

        let hintEnabled = UserDefaults.standard.object(forKey: "autoImport.categorizationHintEnabled") == nil
            ? true : UserDefaults.standard.bool(forKey: "autoImport.categorizationHintEnabled")
        guard hintEnabled else { return }

        guard let allExpenses = try? context.fetch(FetchDescriptor<Expense>()) else { return }
        let count = allExpenses.count

        let storedHint = UserDefaults.standard.string(forKey: "autoImport.categorizationHint") ?? ""
        let storedCount = UserDefaults.standard.integer(forKey: "autoImport.categorizationHintExpenseCount")

        let shouldGenerate = storedHint.isEmpty ? count >= 5 : (count - storedCount) >= 10
        guard shouldGenerate else { return }

        let model = UserDefaults.standard.string(forKey: "autoImport.model")
            ?? "qwen/qwen3-vl-235b-a22b-thinking"
        let maxTokens = UserDefaults.standard.integer(forKey: "autoImport.maxTokens")
        let categories = loadCategories()
        let dataPoints = allExpenses
            .filter { !$0.itemName.isEmpty }
            .map { CategoryDataPoint(label: $0.itemName, category: $0.category) }

        do {
            let hint = try await generateCategorizationHint(
                expenses:   dataPoints,
                categories: categories,
                apiKey:     apiKey,
                model:      model,
                maxTokens:  maxTokens
            )
            UserDefaults.standard.set(hint, forKey: "autoImport.categorizationHint")
            UserDefaults.standard.set(count, forKey: "autoImport.categorizationHintExpenseCount")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "autoImport.categorizationHintLastUpdated")
            #if DEBUG
            print("[AutoImportQueue] Categorization hint updated (\(count) expenses)")
            #endif
        } catch {
            #if DEBUG
            print("[AutoImportQueue] Hint generation failed: \(error)")
            #endif
        }
    }

    // MARK: - Private

    private var currentHint: String? {
        let enabled = UserDefaults.standard.object(forKey: "autoImport.categorizationHintEnabled") == nil
            ? true : UserDefaults.standard.bool(forKey: "autoImport.categorizationHintEnabled")
        return enabled ? UserDefaults.standard.string(forKey: "autoImport.categorizationHint") : nil
    }

    private func apply(_ result: Result<ExtractedDocument, Error>, to item: AutoImportQueueItem) {
        switch result {
        case .success(let document):
            item.documentType = document.documentType
            item.itemName = document.itemName
            item.supplier = document.correspondent
            item.date = document.date
            item.amountCents = document.amountCents
            item.reference = document.reference
            item.category = document.category
            item.state = .ready
        case .failure(let error):
            item.state = .failed(error.localizedDescription)
        }
    }
}
