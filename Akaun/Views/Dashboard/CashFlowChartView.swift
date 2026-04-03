import SwiftUI
import Charts

struct CashFlowChartView: View {
    let data: [MonthlyNetData]

    @State private var selectedLabel: String?
    @State private var cursorLocation: CGPoint = .zero
    @State private var isHovering: Bool = false

    var body: some View {
        GroupBox("Cash Flow") {
            Chart {
                ForEach(data) { item in
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
            .animation(.default, value: data.map(\.netCents))
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
                       let item = data.first(where: { $0.label == label }),
                       item.hasData {
                        tooltipView(label: label, item: item, in: proxy)
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

    @ViewBuilder
    private func tooltipView(label: String, item: MonthlyNetData, in proxy: GeometryProxy) -> some View {
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
