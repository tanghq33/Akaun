import SwiftData
import Foundation

@Model final class ClaimAttachment {
    var filename: String
    var displayName: String
    var addedDate: Date
    var claim: Claim?

    init(filename: String, displayName: String, addedDate: Date = .now) {
        self.filename = filename
        self.displayName = displayName
        self.addedDate = addedDate
    }
}
