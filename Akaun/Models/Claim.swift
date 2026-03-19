import SwiftData
import Foundation

enum ClaimStatus: String, Codable, CaseIterable {
    case pending = "Pending"
    case done = "Done"
}

@Model final class Claim {
    var claimNumber: String
    var date: Date
    var status: ClaimStatus

    @Relationship(deleteRule: .nullify, inverse: \Expense.claim)
    var expenses: [Expense]

    @Relationship(deleteRule: .cascade, inverse: \Attachment.claim)
    var attachments: [Attachment] = []

    var totalAmountCents: Int {
        expenses.reduce(0) { $0 + $1.amountCents }
    }

    init(claimNumber: String = "", date: Date = .now, status: ClaimStatus = .pending) {
        self.claimNumber = claimNumber
        self.date = date
        self.status = status
        self.expenses = []
    }
}
