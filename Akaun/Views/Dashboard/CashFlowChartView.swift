import SwiftUI
import Charts

struct CashFlowChartView: View {
    let expenses: [Expense]
    let incomes: [Income]

    private struct MonthlyNet: Identifiable {
        let id = UUID()
        let label: String
        let net: Double
    }

    private var chartData: [MonthlyNet] {
        let calendar = Calendar.current
        let now = Date.now
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yy"

        var months: [Date] = []
        for offset in stride(from: -5, through: 0, by: 1) {
            if let date = calendar.date(byAdding: .month, value: offset, to: now) {
                let comps = calendar.dateComponents([.year, .month], from: date)
                if let start = calendar.date(from: comps) {
                    months.append(start)
                }
            }
        }

        var data: [MonthlyNet] = []

        for month in months {
            let label = formatter.string(from: month)
            let comps = calendar.dateComponents([.year, .month], from: month)

            let incomeTotal = incomes
                .filter { calendar.dateComponents([.year, .month], from: $0.date) == comps }
                .reduce(0) { $0 + $1.amountCents }

            let expenseTotal = expenses
                .filter { calendar.dateComponents([.year, .month], from: $0.date) == comps }
                .reduce(0) { $0 + $1.amountCents }

            let net = Double(incomeTotal - expenseTotal) / 100.0
            data.append(MonthlyNet(label: label, net: net))
        }

        return data
    }

    var body: some View {
        GroupBox("Cash Flow") {
            Chart {
                ForEach(chartData) { item in
                    BarMark(
                        x: .value("Month", item.label),
                        y: .value("Net (RM)", item.net)
                    )
                    .foregroundStyle(item.net >= 0 ? Color.green : Color.red)
                }
                RuleMark(y: .value("Zero", 0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 200)
            .padding(.top, 8)
            .padding(.horizontal)
        }
        .frame(minWidth: 300, maxHeight: .infinity)
    }
}
