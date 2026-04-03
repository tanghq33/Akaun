import SwiftData
import Foundation

@Model final class IncomeSearchData {
    var text: String
    var income: Income?

    init(text: String) {
        self.text = text
    }
}
