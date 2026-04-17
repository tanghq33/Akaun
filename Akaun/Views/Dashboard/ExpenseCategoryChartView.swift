import SwiftUI
import Charts

struct ExpenseCategoryChartView: View {
    let data: [CategoryData]
    let period: DashboardPeriod

    @State private var selectedAngle: Double?
    @State private var cursorLocation: CGPoint = .zero
    @State private var isHovering: Bool = false

    // Fixed palette — cycles if there are more than 8 categories.
    private static let palette: [Color] = [
        .blue, .orange, .green, .red, .purple, .brown, .pink, .yellow
    ]

    private func color(for category: String) -> Color {
        guard let index = data.firstIndex(where: { $0.category == category }) else { return .gray }
        return Self.palette[index % Self.palette.count]
    }

    private var totalCents: Int { data.reduce(0) { $0 + $1.amountCents } }

    // Map the selected cumulative angle back to whichever slice it falls in.
    private var selectedItem: CategoryData? {
        guard let angle = selectedAngle else { return nil }
        var cumulative = 0.0
        for item in data {
            cumulative += item.amount
            if angle <= cumulative { return item }
        }
        return nil
    }

    @ViewBuilder
    private func tooltipView(in proxy: GeometryProxy) -> some View {
        if isHovering, let item = selectedItem {
            let tooltipWidth: CGFloat = 180
            let tooltipHeight: CGFloat = 70
            let margin: CGFloat = 12
            let xOffset = cursorLocation.x + margin + tooltipWidth > proxy.size.width
                ? cursorLocation.x - margin - tooltipWidth
                : cursorLocation.x + margin
            let yOffset = cursorLocation.y - tooltipHeight < 0
                ? cursorLocation.y + margin
                : cursorLocation.y - tooltipHeight
            let pct = totalCents > 0 ? Double(item.amountCents) / Double(totalCents) * 100.0 : 0.0
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(for: item.category))
                        .frame(width: 8, height: 8)
                    Text(item.category)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(Formatters.formatCents(item.amountCents))
                    .font(.caption.bold())
                Text(String(format: "%.1f%% of total", pct))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 4)
            .offset(x: xOffset, y: yOffset)
            .allowsHitTesting(false)
        }
    }

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
                .chartForegroundStyleScale(
                    domain: data.map(\.category),
                    range: data.indices.map { Self.palette[$0 % Self.palette.count] }
                )
                .chartLegend(position: .bottom, alignment: .center)
                .animation(.default, value: data.map(\.amount))
                .chartAngleSelection(value: $selectedAngle)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        cursorLocation = location
                        isHovering = true
                    case .ended:
                        isHovering = false
                        selectedAngle = nil
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
        }
        .frame(minWidth: 300, maxHeight: .infinity)
    }
}
