import SwiftUI
import Charts

struct MonthlyTrendChartView: View {
    let expenses: [Expense]
    let incomes: [Income]

    @State private var selectedLabel: String?
    @State private var cursorLocation: CGPoint = .zero
    @State private var isHovering: Bool = false

    private struct MonthlyData: Identifiable {
        let id = UUID()
        let month: Date
        let label: String
        let series: String
        let amount: Double
        let amountCents: Int
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

            data.append(MonthlyData(month: month, label: label, series: "Income", amount: Double(incomeTotal) / 100.0, amountCents: incomeTotal))
            data.append(MonthlyData(month: month, label: label, series: "Expenses", amount: Double(expenseTotal) / 100.0, amountCents: expenseTotal))
        }

        return data
    }

    @ViewBuilder
    private var tooltipView: some View {
        if isHovering, let label = selectedLabel,
           let incomeItem = chartData.first(where: { $0.label == label && $0.series == "Income" }),
           let expenseItem = chartData.first(where: { $0.label == label && $0.series == "Expenses" }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("Income:   \(Formatters.formatCents(incomeItem.amountCents))")
                        .font(.caption)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("Expenses: \(Formatters.formatCents(expenseItem.amountCents))")
                        .font(.caption)
                }
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 4)
            .offset(x: cursorLocation.x + 12, y: cursorLocation.y - 40)
            .allowsHitTesting(false)
        }
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
            .chartXSelection(value: $selectedLabel)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    cursorLocation = location
                    isHovering = true
                case .ended:
                    isHovering = false
                    selectedLabel = nil
                }
            }
            .overlay(alignment: .topLeading) {
                tooltipView
            }
            .clipped()
            .frame(minHeight: 200)
            .padding(.top, 8)
            .padding(.horizontal)
        }
        .frame(minWidth: 300, maxHeight: .infinity)
    }
}
