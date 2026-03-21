import SwiftUI

struct IncomeRowView: View {
    let income: Income

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(income.incomeNumber)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Formatters.formatCents(income.amountCents))
                    .font(.body)
                    .foregroundStyle(.green)
            }
            Text(income.descriptionText.isEmpty ? "Unnamed" : income.descriptionText)
                .font(.body)
            HStack {
                Text(income.source.isEmpty ? Formatters.displayDate.string(from: income.date) : income.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !income.category.isEmpty {
                    Text(income.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
