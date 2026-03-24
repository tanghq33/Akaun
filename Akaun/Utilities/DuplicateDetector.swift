import Foundation
import SwiftData

struct DuplicateMatch: Equatable {
    enum Reason: Equatable {
        case filename(existingDisplayName: String)
        case reference(value: String)
        case amountDateSupplier
    }

    var reasons: [Reason]
    var existingRecordNumber: String
    var existingDate: Date
    var existingAmountCents: Int
}

enum DuplicateDetector {
    static func findMatches(
        for item: AutoImportQueueItem,
        expenses: [Expense],
        incomes: [Income]
    ) -> [DuplicateMatch] {
        switch item.documentType {
        case .expense:
            return checkExpenses(item: item, expenses: expenses)
        case .income:
            return checkIncomes(item: item, incomes: incomes)
        }
    }

    // MARK: - Private

    private static func checkExpenses(item: AutoImportQueueItem, expenses: [Expense]) -> [DuplicateMatch] {
        let sourceFilename = item.sourceFile.lastPathComponent.lowercased()
        let itemRef = item.reference.lowercased()
        var matches: [DuplicateMatch] = []

        for expense in expenses {
            var reasons: [DuplicateMatch.Reason] = []

            // Filename signal
            if expense.attachments.contains(where: {
                $0.displayName.lowercased() == sourceFilename
            }) {
                reasons.append(.filename(existingDisplayName: item.sourceFile.lastPathComponent))
            }

            // Reference signal
            if !item.reference.isEmpty,
               !expense.reference.isEmpty,
               expense.reference.lowercased() == itemRef {
                reasons.append(.reference(value: item.reference))
            }

            // Amount + date + supplier signal
            if reasons.isEmpty,
               expense.amountCents == item.amountCents,
               !item.supplier.isEmpty,
               expense.supplier.lowercased() == item.supplier.lowercased(),
               Calendar.current.isDate(expense.date, inSameDayAs: item.date) {
                reasons.append(.amountDateSupplier)
            }

            if !reasons.isEmpty {
                matches.append(DuplicateMatch(
                    reasons: reasons,
                    existingRecordNumber: expense.expenseNumber,
                    existingDate: expense.date,
                    existingAmountCents: expense.amountCents
                ))
            }
        }

        return matches
    }

    private static func checkIncomes(item: AutoImportQueueItem, incomes: [Income]) -> [DuplicateMatch] {
        let sourceFilename = item.sourceFile.lastPathComponent.lowercased()
        let itemRef = item.reference.lowercased()
        var matches: [DuplicateMatch] = []

        for income in incomes {
            var reasons: [DuplicateMatch.Reason] = []

            // Filename signal
            if income.attachments.contains(where: {
                $0.displayName.lowercased() == sourceFilename
            }) {
                reasons.append(.filename(existingDisplayName: item.sourceFile.lastPathComponent))
            }

            // Reference signal
            if !item.reference.isEmpty,
               !income.reference.isEmpty,
               income.reference.lowercased() == itemRef {
                reasons.append(.reference(value: item.reference))
            }

            // Amount + date + supplier signal
            if reasons.isEmpty,
               income.amountCents == item.amountCents,
               !item.supplier.isEmpty,
               income.source.lowercased() == item.supplier.lowercased(),
               Calendar.current.isDate(income.date, inSameDayAs: item.date) {
                reasons.append(.amountDateSupplier)
            }

            if !reasons.isEmpty {
                matches.append(DuplicateMatch(
                    reasons: reasons,
                    existingRecordNumber: income.incomeNumber,
                    existingDate: income.date,
                    existingAmountCents: income.amountCents
                ))
            }
        }

        return matches
    }
}
