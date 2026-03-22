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

    init(sourceFile: URL) {
        self.sourceFile = sourceFile
    }
}

// MARK: - Queue

@Observable
final class AutoImportQueue {
    var items: [AutoImportQueueItem] = []

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
        items.removeAll { $0.id == item.id }
    }

    func enqueue(
        _ urls: [URL],
        apiKey: String,
        model: String,
        maxTokens: Int,
        expenseCategories: [String] = [],
        incomeCategories: [String] = []
    ) {
        let storedHint = UserDefaults.standard.string(forKey: "autoImport.categorizationHint")
        let hintEnabled = UserDefaults.standard.object(forKey: "autoImport.categorizationHintEnabled") == nil
            ? true : UserDefaults.standard.bool(forKey: "autoImport.categorizationHintEnabled")
        let hint = hintEnabled ? storedHint : nil

        for url in urls {
            let item = AutoImportQueueItem(sourceFile: url)
            items.append(item)
            Task {
                let result = await processSingleFile(
                    url: url,
                    apiKey: apiKey,
                    model: model,
                    maxTokens: maxTokens,
                    expenseCategories: expenseCategories,
                    incomeCategories: incomeCategories,
                    hint: hint,
                    onStateChange: { item.state = $0 }
                )
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
        let storedHint = UserDefaults.standard.string(forKey: "autoImport.categorizationHint")
        let hintEnabled = UserDefaults.standard.object(forKey: "autoImport.categorizationHintEnabled") == nil
            ? true : UserDefaults.standard.bool(forKey: "autoImport.categorizationHintEnabled")
        let hint = hintEnabled ? storedHint : nil

        item.state = .extracting
        item.documentType = .expense
        item.itemName = ""
        item.supplier = ""
        item.category = "Other"
        Task {
            let result = await processSingleFile(
                url: item.sourceFile,
                apiKey: apiKey,
                model: model,
                maxTokens: maxTokens,
                expenseCategories: expenseCategories,
                incomeCategories: incomeCategories,
                hint: hint,
                onStateChange: { item.state = $0 }
            )
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
            }

            try context.save()
            item.state = .imported
        } catch {
            item.state = .failed(error.localizedDescription)
        }
    }

    func importAllReady(in context: ModelContext) {
        for item in items where item.state == .ready {
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
