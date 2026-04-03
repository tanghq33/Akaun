import SwiftData
import Foundation

enum ExpenseStatus: String, Codable, CaseIterable {
    case unpaid = "Unpaid"
    case pending = "Pending"
    case paid = "Paid"
}

@Model final class Expense {
    var expenseNumber: String
    var itemName: String
    var supplier: String
    var date: Date
    var amountCents: Int
    var reference: String
    var status: ExpenseStatus
    var documentFilename: String?
    var remark: String
    var category: String = "Other"
    var claim: Claim?

    @Relationship(deleteRule: .cascade, inverse: \ExpenseSearchData.expense)
    var searchData: ExpenseSearchData?

    @Relationship(deleteRule: .cascade, inverse: \Attachment.expense)
    var attachments: [Attachment] = []

    init(
        expenseNumber: String = "",
        itemName: String = "",
        supplier: String = "",
        date: Date = .now,
        amountCents: Int = 0,
        reference: String = "",
        status: ExpenseStatus = .unpaid,
        documentFilename: String? = nil,
        remark: String = "",
        category: String = "Other"
    ) {
        self.expenseNumber = expenseNumber
        self.itemName = itemName
        self.supplier = supplier
        self.date = date
        self.amountCents = amountCents
        self.reference = reference
        self.status = status
        self.documentFilename = documentFilename
        self.remark = remark
        self.category = category
    }
}
