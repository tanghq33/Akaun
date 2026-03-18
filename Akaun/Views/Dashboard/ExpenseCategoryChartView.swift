import SwiftUI
import Charts

struct ExpenseCategoryChartView: View {
    let expenses: [Expense]
    let incomes: [Income]

    private struct CategoryData: Identifiable {
        let id = UUID()
        let category: String
        let amount: Double
    }

    private var chartData: [CategoryData] {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: Date.now)

        var totals: [String: Int] = [:]
        for expense in expenses {
            let eComps = calendar.dateComponents([.year, .month], from: expense.date)
            guard eComps == comps else { continue }
            totals[expense.category, default: 0] += expense.amountCents
        }

        return totals
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { CategoryData(category: $0.key, amount: Double($0.value) / 100.0) }
    }

    var body: some View {
        GroupBox("Expenses by Category") {
            if chartData.isEmpty {
                ContentUnavailableView("No expenses this month", systemImage: "chart.pie")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal)
            } else {
                Chart(chartData) { item in
                    SectorMark(
                        angle: .value("Amount", item.amount),
                        innerRadius: .ratio(0.5)
                    )
                    .foregroundStyle(by: .value("Category", item.category))
                }
                .chartLegend(position: .bottom, alignment: .center)
                .frame(minHeight: 200)
                .padding(.top, 8)
                .padding(.horizontal)
            }
        }
        .frame(minWidth: 300, maxHeight: .infinity)
    }
}
