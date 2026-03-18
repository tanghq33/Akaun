import SwiftData
import Foundation

@Model final class Income {
    var incomeNumber: String
    var date: Date
    var amountCents: Int
    var remark: String

    init(incomeNumber: String = "", date: Date = .now, amountCents: Int = 0, remark: String = "") {
        self.incomeNumber = incomeNumber
        self.date = date
        self.amountCents = amountCents
        self.remark = remark
    }
}
