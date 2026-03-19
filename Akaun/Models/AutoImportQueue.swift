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

    func enqueue(_ urls: [URL], apiKey: String, model: String, maxTokens: Int, categories: [String] = []) {
        for url in urls {
            let item = AutoImportQueueItem(sourceFile: url)
            items.append(item)
            Task {
                let result = await processSingleFile(
                    url: url,
                    apiKey: apiKey,
                    model: model,
                    maxTokens: maxTokens,
                    categories: categories,
                    onStateChange: { item.state = $0 }
                )
                apply(result, to: item)
            }
        }
    }

    func retryItem(_ item: AutoImportQueueItem, apiKey: String, model: String, maxTokens: Int, categories: [String] = []) {
        item.state = .extracting
        item.itemName = ""
        item.supplier = ""
        item.category = "Other"
        Task {
            let result = await processSingleFile(
                url: item.sourceFile,
                apiKey: apiKey,
                model: model,
                maxTokens: maxTokens,
                categories: categories,
                onStateChange: { item.state = $0 }
            )
            apply(result, to: item)
        }
    }

    func importItem(_ item: AutoImportQueueItem, in context: ModelContext) {
        do {
            let filename = try DocumentStore.importFile(from: item.sourceFile)
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
            try? context.save()
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

    // MARK: - Private

    private func apply(_ result: Result<ExtractedReceipt, Error>, to item: AutoImportQueueItem) {
        switch result {
        case .success(let receipt):
            item.itemName = receipt.itemName
            item.supplier = receipt.supplier
            item.date = receipt.date
            item.amountCents = receipt.amountCents
            item.reference = receipt.reference
            item.category = receipt.category
            item.state = .ready
        case .failure(let error):
            item.state = .failed(error.localizedDescription)
        }
    }
}
