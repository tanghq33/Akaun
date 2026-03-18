import SwiftUI
import SwiftData

struct ClaimDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigationModel.self) private var nav

    let claimID: PersistentIdentifier

    @State private var showingEditForm = false
    @State private var showingDeleteConfirm = false

    private var claim: Claim? {
        modelContext.model(for: claimID) as? Claim
    }

    var body: some View {
        Group {
            if let claim {
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

                        ForEach(claim.expenses.sorted(by: { $0.date < $1.date })) { expense in
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
                    }
                    .padding()
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") { showingEditForm = true }
                    }
                    ToolbarItem {
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .sheet(isPresented: $showingEditForm) {
                    ClaimFormView(mode: .edit(claim))
                }
                .confirmationDialog("Delete Claim?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        nav.selectedClaimID = nil
                        modelContext.delete(claim)
                    }
                } message: {
                    Text("Linked expenses will remain but will no longer be part of this claim.")
                }
            } else {
                ContentUnavailableView("Claim Not Found", systemImage: "list.bullet.clipboard")
            }
        }
        .navigationTitle(claim?.claimNumber ?? "Claim")
    }
}
