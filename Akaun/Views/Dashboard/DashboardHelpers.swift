import Foundation
import SwiftData

// MARK: - Shared Data Types

struct MonthlyNetData: Identifiable {
    var id: String { label }
    let label: String
    let net: Double
    let netCents: Int
    let hasData: Bool
}

struct MonthlySeriesData: Identifiable {
    var id: String { "\(label)-\(series)" }
    let label: String
    let series: String
    let amount: Double
    let amountCents: Int
}

struct CategoryData: Identifiable {
    var id: String { category }
    let category: String
    let amount: Double
}

// MARK: - Shared Formatters

extension DateFormatter {
    static let dashboardMonthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yy"
        return f
    }()
}

// MARK: - Period Helpers

extension DashboardPeriod {
    /// Month offset from current month. `nil` for `.currentYear`.
    var monthOffset: Int? {
        switch self {
        case .currentMonth: return 0
        case .monthMinus1:  return -1
        case .monthMinus2:  return -2
        case .currentYear:  return nil
        }
    }
}

// MARK: - Month Building

/// Builds the array of month-start `Date` values covered by `period`.
/// For monthly periods: 6 months ending at the anchor month.
/// For `.currentYear`: all 12 months of the current year.
func buildDashboardMonths(period: DashboardPeriod) -> [Date] {
    let cal = Calendar.current
    var months: [Date] = []
    switch period {
    case .currentMonth, .monthMinus1, .monthMinus2:
        let anchor = period.monthOffset ?? 0
        for offset in stride(from: anchor - 5, through: anchor, by: 1) {
            if let d = cal.date(byAdding: .month, value: offset, to: Date.now),
               let start = cal.date(from: cal.dateComponents([.year, .month], from: d)) {
                months.append(start)
            }
        }
    case .currentYear:
        let year = cal.component(.year, from: Date.now)
        for month in 1...12 {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            if let start = cal.date(from: comps) { months.append(start) }
        }
    }
    return months
}

// MARK: - Data Computation

func computeCashFlowData(expenses: [Expense], incomes: [Income], period: DashboardPeriod) -> [MonthlyNetData] {
    let calendar = Calendar.current
    let formatter = DateFormatter.dashboardMonthYear
    return buildDashboardMonths(period: period).map { month in
        let comps = calendar.dateComponents([.year, .month], from: month)
        let label = formatter.string(from: month)
        let incomeTotal = incomes
            .filter { calendar.dateComponents([.year, .month], from: $0.date) == comps }
            .reduce(0) { $0 + $1.amountCents }
        let expenseTotal = expenses
            .filter { calendar.dateComponents([.year, .month], from: $0.date) == comps }
            .reduce(0) { $0 + $1.amountCents }
        let netCents = incomeTotal - expenseTotal
        return MonthlyNetData(
            label: label,
            net: Double(netCents) / 100.0,
            netCents: netCents,
            hasData: incomeTotal > 0 || expenseTotal > 0
        )
    }
}

func computeTrendData(expenses: [Expense], incomes: [Income], period: DashboardPeriod) -> [MonthlySeriesData] {
    let calendar = Calendar.current
    if period == .currentYear {
        let currentYear = calendar.component(.year, from: Date.now)
        var data: [MonthlySeriesData] = []
        for year in (currentYear - 4)...currentYear {
            let label = String(year)
            let incomeTotal = incomes
                .filter { calendar.component(.year, from: $0.date) == year }
                .reduce(0) { $0 + $1.amountCents }
            let expenseTotal = expenses
                .filter { calendar.component(.year, from: $0.date) == year }
                .reduce(0) { $0 + $1.amountCents }
            data.append(MonthlySeriesData(label: label, series: "Income",   amount: Double(incomeTotal)  / 100.0, amountCents: incomeTotal))
            data.append(MonthlySeriesData(label: label, series: "Expenses", amount: Double(expenseTotal) / 100.0, amountCents: expenseTotal))
        }
        return data
    } else {
        let formatter = DateFormatter.dashboardMonthYear
        return buildDashboardMonths(period: period).flatMap { month -> [MonthlySeriesData] in
            let comps = calendar.dateComponents([.year, .month], from: month)
            let label = formatter.string(from: month)
            let incomeTotal = incomes
                .filter { calendar.dateComponents([.year, .month], from: $0.date) == comps }
                .reduce(0) { $0 + $1.amountCents }
            let expenseTotal = expenses
                .filter { calendar.dateComponents([.year, .month], from: $0.date) == comps }
                .reduce(0) { $0 + $1.amountCents }
            return [
                MonthlySeriesData(label: label, series: "Income",   amount: Double(incomeTotal)  / 100.0, amountCents: incomeTotal),
                MonthlySeriesData(label: label, series: "Expenses", amount: Double(expenseTotal) / 100.0, amountCents: expenseTotal)
            ]
        }
    }
}

func computeCategoryData(expenses: [Expense], period: DashboardPeriod) -> [CategoryData] {
    let calendar = Calendar.current
    var totals: [String: Int] = [:]
    switch period {
    case .currentMonth, .monthMinus1, .monthMinus2:
        let offset = period.monthOffset ?? 0
        guard let targetDate = calendar.date(byAdding: .month, value: offset, to: Date.now) else { break }
        let comps = calendar.dateComponents([.year, .month], from: targetDate)
        for expense in expenses {
            guard calendar.dateComponents([.year, .month], from: expense.date) == comps else { continue }
            totals[expense.category, default: 0] += expense.amountCents
        }
    case .currentYear:
        let year = calendar.component(.year, from: Date.now)
        for expense in expenses {
            guard calendar.component(.year, from: expense.date) == year else { continue }
            totals[expense.category, default: 0] += expense.amountCents
        }
    }
    return totals
        .filter { $0.value > 0 }
        .sorted { $0.value > $1.value }
        .map { CategoryData(category: $0.key, amount: Double($0.value) / 100.0) }
}

func computePeriodTotals(expenses: [Expense], incomes: [Income], period: DashboardPeriod) -> (incomeCents: Int, expenseCents: Int) {
    let calendar = Calendar.current
    if let offset = period.monthOffset,
       let targetDate = calendar.date(byAdding: .month, value: offset, to: Date.now) {
        let comps = calendar.dateComponents([.year, .month], from: targetDate)
        let income = incomes
            .filter { calendar.dateComponents([.year, .month], from: $0.date) == comps }
            .reduce(0) { $0 + $1.amountCents }
        let expense = expenses
            .filter { calendar.dateComponents([.year, .month], from: $0.date) == comps }
            .reduce(0) { $0 + $1.amountCents }
        return (income, expense)
    } else {
        let year = calendar.component(.year, from: Date.now)
        let income = incomes
            .filter { calendar.component(.year, from: $0.date) == year }
            .reduce(0) { $0 + $1.amountCents }
        let expense = expenses
            .filter { calendar.component(.year, from: $0.date) == year }
            .reduce(0) { $0 + $1.amountCents }
        return (income, expense)
    }
}
