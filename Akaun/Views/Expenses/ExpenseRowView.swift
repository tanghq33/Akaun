import SwiftUI

struct ExpenseRowView: View {
    let expense: Expense

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(expense.expenseNumber)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Formatters.formatCents(expense.amountCents))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            Text(expense.itemName.isEmpty ? "Unnamed" : expense.itemName)
                .font(.body)
            HStack {
                Text(expense.supplier.isEmpty ? "—" : expense.supplier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                StatusBadge(text: expense.status.rawValue, color: statusColor(expense.status))
            }
        }
        .padding(.vertical, 2)
    }

    private func statusColor(_ status: ExpenseStatus) -> Color {
        switch status {
        case .unpaid: return .red
        case .paid: return .green
        }
    }
}

