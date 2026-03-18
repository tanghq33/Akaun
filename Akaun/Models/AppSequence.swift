import SwiftData

@Model final class AppSequence {
    var prefix: String
    var dateKey: String
    var lastSequence: Int

    init(prefix: String, dateKey: String, lastSequence: Int = 0) {
        self.prefix = prefix
        self.dateKey = dateKey
        self.lastSequence = lastSequence
    }
}
