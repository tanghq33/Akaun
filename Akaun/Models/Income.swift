import SwiftData
import Foundation

@Model final class Income {
    var incomeNumber: String
    var source: String
    var descriptionText: String
    var date: Date
    var amountCents: Int
    var reference: String
    var category: String
    var remark: String

    @Relationship(deleteRule: .cascade, inverse: \IncomeSearchData.income)
    var searchData: IncomeSearchData?

    @Relationship(deleteRule: .cascade, inverse: \IncomeAttachment.income)
    var attachments: [IncomeAttachment] = []

    init(
        incomeNumber: String = "",
        source: String = "",
        descriptionText: String = "",
        date: Date = .now,
        amountCents: Int = 0,
        reference: String = "",
        category: String = "Other",
        remark: String = ""
    ) {
        self.incomeNumber = incomeNumber
        self.source = source
        self.descriptionText = descriptionText
        self.date = date
        self.amountCents = amountCents
        self.reference = reference
        self.category = category
        self.remark = remark
    }
}
