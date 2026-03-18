import Foundation

enum Formatters {
    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "MYR"
        f.currencySymbol = "RM"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static let displayDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// Convert integer cents to a display string, e.g. 1050 → "RM 10.50"
    static func formatCents(_ cents: Int) -> String {
        let value = Decimal(cents) / 100
        return currency.string(from: value as NSDecimalNumber) ?? "RM 0.00"
    }
}
