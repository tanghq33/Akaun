import SwiftData
import Foundation

@Model final class ClaimSearchData {
    var text: String
    var claim: Claim?

    init(text: String) {
        self.text = text
    }
}
