import SwiftUI
import SwiftData

struct ClaimDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigationModel.self) private var nav

    let claimID: PersistentIdentifier

    @State private var showingClaimSheet = false
    @State private var showingDeleteConfirm = false

    private var claim: Claim? {
        modelContext.model(for: claimID) as? Claim
    }

    var body: some View {
        Group {
            if let claim {
                let sortedExpenses = claim.expenses.sorted { $0.date < $1.date }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(claim.claimNumber)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text(Formatters.displayDate.string(from: claim.date))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(
                                text: claim.status.rawValue,
                                color: claim.status == .pending ? .orange : .green
                            )
                        }

                        HStack {
                            Text("Total")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Formatters.formatCents(claim.totalAmountCents))
                                .font(.title3)
                                .fontWeight(.semibold)
                        }

                        Divider()

                        Text("Expenses (\(claim.expenses.count))")
                            .font(.headline)

                        ForEach(sortedExpenses) { expense in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(expense.itemName.isEmpty ? "Unnamed" : expense.itemName)
                                    Text(expense.expenseNumber)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Formatters.formatCents(expense.amountCents))
                            }
                            .padding(.vertical, 2)
                            Divider()
                        }

                        AttachmentListView(claimAttachments: claim.claimAttachments)
                    }
                    .padding()
                }
                .toolbar {
                    if claim.status == .pending {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                showingClaimSheet = true
                            } label: {
                                Label("Mark as Claimed", systemImage: "checkmark.circle")
                            }
                        }
                    }
                    ToolbarItem {
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .sheet(isPresented: $showingClaimSheet) {
                    ClaimConfirmationView(claim: claim)
                }
                .confirmationDialog("Delete Claim?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        deleteClaim(claim)
                    }
                } message: {
                    Text("Linked expenses will revert to Unpaid. Claim attachments will be deleted.")
                }
            } else {
                ContentUnavailableView("Claim Not Found", systemImage: "list.bullet.clipboard")
            }
        }
        .navigationTitle(claim?.claimNumber ?? "Claim")
    }

    private func deleteClaim(_ claim: Claim) {
        // Revert linked expenses to unpaid
        for expense in claim.expenses {
            expense.status = .unpaid
        }
        DocumentStore.deleteFiles(for: claim.claimAttachments)
        nav.selectedClaimID = nil
        modelContext.delete(claim)
    }
}
