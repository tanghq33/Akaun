import SwiftUI

struct IncomeRowView: View {
    let income: Income

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(income.incomeNumber)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(Formatters.displayDate.string(from: income.date))
                    .font(.body)
                Spacer()
                Text(Formatters.formatCents(income.amountCents))
                    .font(.body)
                    .foregroundStyle(.green)
            }
            if !income.remark.isEmpty {
                Text(income.remark)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
