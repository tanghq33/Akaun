import SwiftUI

struct ProfitThisMonthView: View {
    let expenses: [Expense]
    let incomes: [Income]

    private var currentMonthComponents: DateComponents {
        Calendar.current.dateComponents([.year, .month], from: Date.now)
    }

    private var incomeCents: Int {
        let comps = currentMonthComponents
        return incomes
            .filter { Calendar.current.dateComponents([.year, .month], from: $0.date) == comps }
            .reduce(0) { $0 + $1.amountCents }
    }

    private var expenseCents: Int {
        let comps = currentMonthComponents
        return expenses
            .filter { Calendar.current.dateComponents([.year, .month], from: $0.date) == comps }
            .reduce(0) { $0 + $1.amountCents }
    }

    private var profitCents: Int {
        incomeCents - expenseCents
    }

    var body: some View {
        GroupBox("Profit This Month") {
            VStack(spacing: 16) {
                Spacer()

                Text(Formatters.formatCents(abs(profitCents)))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(profitCents >= 0 ? Color.green : Color.red)

                if profitCents < 0 {
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
