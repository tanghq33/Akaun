import SwiftUI
import Charts

struct MonthlyTrendChartView: View {
    let expenses: [Expense]
    let incomes: [Income]

    private struct MonthlyData: Identifiable {
        let id = UUID()
        let month: Date
        let label: String
        let series: String
        let amount: Double
    }

    private var chartData: [MonthlyData] {
        let calendar = Calendar.current
        let now = Date.now
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yy"

        // Build last 6 months
        var months: [Date] = []
        for offset in stride(from: -5, through: 0, by: 1) {
            if let date = calendar.date(byAdding: .month, value: offset, to: now) {
                let comps = calendar.dateComponents([.year, .month], from: date)
                if let start = calendar.date(from: comps) {
                    months.append(start)
                }
            }
        }

        var data: [MonthlyData] = []

        for month in months {
            let label = formatter.string(from: month)
            let comps = calendar.dateComponents([.year, .month], from: month)

            let incomeTotal = incomes
                .filter { calendar.dateComponents([.year, .month], from: $0.date) == comps }
                .reduce(0) { $0 + $1.amountCents }

            let expenseTotal = expenses
                .filter { calendar.dateComponents([.year, .month], from: $0.date) == comps }
                .reduce(0) { $0 + $1.amountCents }

            data.append(MonthlyData(month: month, label: label, series: "Income", amount: Double(incomeTotal) / 100.0))
            data.append(MonthlyData(month: month, label: label, series: "Expenses", amount: Double(expenseTotal) / 100.0))
        }

        return data
    }

    var body: some View {
        GroupBox("Monthly Trend") {
            Chart(chartData) { item in
                BarMark(
                    x: .value("Month", item.label),
                    y: .value("Amount (RM)", item.amount)
                )
                .foregroundStyle(by: .value("Type", item.series))
                .position(by: .value("Type", item.series))
            }
            .chartForegroundStyleScale([
                "Income": Color.green,
                "Expenses": Color.red,
            ])
            .frame(minHeight: 200)
            .padding(.top, 8)
            .padding(.horizontal)
        }
        .frame(minWidth: 300, maxHeight: .infinity)
    }
}
