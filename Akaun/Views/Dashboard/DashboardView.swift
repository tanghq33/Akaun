import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]

    var body: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                MonthlyTrendChartView(expenses: expenses, incomes: incomes)
                ProfitThisMonthView(expenses: expenses, incomes: incomes)
            }
            GridRow {
                ExpenseCategoryChartView(expenses: expenses, incomes: incomes)
                CashFlowChartView(expenses: expenses, incomes: incomes)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Dashboard")
    }
}
