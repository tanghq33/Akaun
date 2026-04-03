import SwiftUI
import Charts

struct MonthlyTrendChartView: View {
    let data: [MonthlySeriesData]
    let period: DashboardPeriod

    @State private var selectedLabel: String?
    @State private var cursorLocation: CGPoint = .zero
    @State private var isHovering: Bool = false

    @ViewBuilder
    private func tooltipView(in proxy: GeometryProxy) -> some View {
        if isHovering, let label = selectedLabel,
           let incomeItem = data.first(where: { $0.label == label && $0.series == "Income" }),
           let expenseItem = data.first(where: { $0.label == label && $0.series == "Expenses" }),
           incomeItem.amountCents > 0 || expenseItem.amountCents > 0 {
            let tooltipWidth: CGFloat = 190
            let tooltipHeight: CGFloat = 68
            let margin: CGFloat = 12
            let xOffset = cursorLocation.x + margin + tooltipWidth > proxy.size.width
                ? cursorLocation.x - margin - tooltipWidth
                : cursorLocation.x + margin
            let yOffset = cursorLocation.y - tooltipHeight < 0
                ? cursorLocation.y + margin
                : cursorLocation.y - tooltipHeight
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
            .offset(x: xOffset, y: yOffset)
            .allowsHitTesting(false)
        }
    }

    var body: some View {
        GroupBox(period == .currentYear ? "Yearly Trend" : "Monthly Trend") {
            Chart(data) { item in
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
            .animation(.default, value: data.map(\.amountCents))
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
                    tooltipView(in: proxy)
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
