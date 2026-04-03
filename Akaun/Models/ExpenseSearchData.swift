import SwiftData
import Foundation

@Model final class ExpenseSearchData {
    var text: String
    var expense: Expense?

    init(text: String) {
        self.text = text
    }
}
