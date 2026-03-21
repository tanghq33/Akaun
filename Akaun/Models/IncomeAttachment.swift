import SwiftData
import Foundation

@Model final class IncomeAttachment {
    var filename: String
    var displayName: String
    var addedDate: Date
    var income: Income?

    init(filename: String, displayName: String, addedDate: Date = .now) {
        self.filename = filename
        self.displayName = displayName
        self.addedDate = addedDate
    }
}
