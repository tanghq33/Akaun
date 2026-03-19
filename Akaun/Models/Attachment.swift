import SwiftData
import Foundation

@Model final class Attachment {
    var filename: String
    var displayName: String
    var addedDate: Date
    var expense: Expense?
    var claim: Claim?

    init(filename: String, displayName: String, addedDate: Date = .now) {
        self.filename = filename
        self.displayName = displayName
        self.addedDate = addedDate
    }
}
