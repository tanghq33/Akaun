import SwiftUI

struct ClaimRowView: View {
    let claim: Claim

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(claim.claimNumber)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Formatters.formatCents(claim.totalAmountCents))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            HStack {
                Text(Formatters.displayDate.string(from: claim.date))
                    .font(.body)
                Spacer()
                StatusBadge(
                    text: claim.status.rawValue,
                    color: claim.status == .pending ? .orange : .green
                )
            }
            Text("\(claim.expenses.count) expense\(claim.expenses.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
