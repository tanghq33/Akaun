import SwiftData
import Foundation

enum RunningNumberGenerator {
    static func next(prefix: String, for date: Date, in context: ModelContext) -> String {
        let dateKey = dateKeyFormatter.string(from: date)

        var descriptor = FetchDescriptor<AppSequence>(
            predicate: #Predicate { $0.prefix == prefix && $0.dateKey == dateKey }
        )
        descriptor.fetchLimit = 1

        let existing = try? context.fetch(descriptor)
        let sequence: AppSequence
        if let found = existing?.first {
            sequence = found
        } else {
            sequence = AppSequence(prefix: prefix, dateKey: dateKey, lastSequence: 0)
            context.insert(sequence)
        }

        sequence.lastSequence += 1
        let padded = String(format: "%03d", sequence.lastSequence)
        return "\(prefix)\(dateKey)-\(padded)"
    }

    private static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
