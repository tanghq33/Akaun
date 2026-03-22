import SwiftUI
import Charts

struct CashFlowChartView: View {
    let expenses: [Expense]
    let incomes: [Income]

    @State private var selectedLabel: String?
    @State private var cursorLocation: CGPoint = .zero
    @State private var isHovering: Bool = false

    private struct MonthlyNet: Identifiable {
        let id = UUID()
        let label: String
        let net: Double
        let netCents: Int
        let hasData: Bool
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

            let netCents = incomeTotal - expenseTotal
            let net = Double(netCents) / 100.0
            data.append(MonthlyNet(label: label, net: net, netCents: netCents, hasData: incomeTotal > 0 || expenseTotal > 0))
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
                GeometryReader { proxy in
                    if isHovering, let label = selectedLabel,
                       let item = chartData.first(where: { $0.label == label }),
                       item.hasData {
                        let tooltipWidth: CGFloat = 160
                        let tooltipHeight: CGFloat = 52
                        let margin: CGFloat = 12
                        let xOffset = cursorLocation.x + margin + tooltipWidth > proxy.size.width
                            ? cursorLocation.x - margin - tooltipWidth
                            : cursorLocation.x + margin
                        let yOffset = cursorLocation.y - tooltipHeight < 0
                            ? cursorLocation.y + margin
                            : cursorLocation.y - tooltipHeight
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("Net: \(Formatters.formatCents(item.netCents))")
                                .font(.caption)
                                .foregroundStyle(item.netCents >= 0 ? .primary : Color.red)
                        }
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 4)
                        .offset(x: xOffset, y: yOffset)
                        .allowsHitTesting(false)
                    }
                }
            }
            .clipped()
            .frame(minHeight: 200)
            .padding(.top, 8)
            .padding(.horizontal)
        }
        .frame(minWidth: 300, maxHeight: .infinity)
    }
}
