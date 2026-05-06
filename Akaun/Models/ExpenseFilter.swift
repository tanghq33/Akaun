import Foundation

struct ExpenseFilter: Equatable {
    var statuses: Set<ExpenseStatus> = []
    var categories: Set<String> = []
    var dateFrom: Date? = nil
    var dateTo: Date? = nil
    var amountMinCents: Int? = nil
    var amountMaxCents: Int? = nil

    var isActive: Bool {
        !statuses.isEmpty || !categories.isEmpty ||
        dateFrom != nil || dateTo != nil ||
        amountMinCents != nil || amountMaxCents != nil
    }

    init(
        statuses: Set<ExpenseStatus> = [],
        categories: Set<String> = [],
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        amountMinCents: Int? = nil,
        amountMaxCents: Int? = nil
    ) {
        self.statuses = statuses
        self.categories = categories
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.amountMinCents = amountMinCents
        self.amountMaxCents = amountMaxCents
    }

    mutating func clear() {
        self = ExpenseFilter()
    }
}
