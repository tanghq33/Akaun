import SwiftUI
import Charts

struct ExpenseCategoryChartView: View {
    let data: [CategoryData]
    let period: DashboardPeriod

    var body: some View {
        GroupBox("Expenses by Category") {
            if data.isEmpty {
                ContentUnavailableView("No expenses for \(period.label)", systemImage: "chart.pie")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal)
            } else {
                Chart(data) { item in
                    SectorMark(
                        angle: .value("Amount", item.amount),
                        innerRadius: .ratio(0.5)
                    )
                    .foregroundStyle(by: .value("Category", item.category))
                }
                .chartLegend(position: .bottom, alignment: .center)
                .animation(.default, value: data.map(\.amount))
                .frame(minHeight: 200)
                .padding(.top, 8)
                .padding(.horizontal)
            }
        }
        .frame(minWidth: 300, maxHeight: .infinity)
    }
}
