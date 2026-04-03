import SwiftUI

struct ProfitThisMonthView: View {
    let incomeCents: Int
    let expenseCents: Int
    let period: DashboardPeriod

    private var profitCents: Int { incomeCents - expenseCents }

    var body: some View {
        GroupBox("Profit") {
            VStack(spacing: 16) {
                Spacer()

                let isLoss = profitCents < 0
                Text(isLoss ? "- \(Formatters.formatCents(abs(profitCents)))" : Formatters.formatCents(profitCents))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(isLoss ? Color.red : Color.green)

                if isLoss {
                    Text("Loss")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Divider()

                HStack {
                    VStack(alignment: .leading) {
                        Text("Income")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Formatters.formatCents(incomeCents))
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Expenses")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Formatters.formatCents(expenseCents))
                            .foregroundStyle(.red)
                    }
                }

                Spacer()
            }
            .padding(.top, 8)
            .padding(.horizontal)
        }
        .frame(minWidth: 300, maxHeight: .infinity)
    }
}
