import SwiftUI
import SwiftData

struct ExpenseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigationModel.self) private var nav

    let expenseID: PersistentIdentifier

    @State private var showingEditForm = false
    @State private var showingDeleteConfirm = false

    private var expense: Expense? {
        modelContext.model(for: expenseID) as? Expense
    }

    var body: some View {
        Group {
            if let expense {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        HStack {
                            VStack(alignment: .leading) {
                                Text(expense.expenseNumber)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text(Formatters.displayDate.string(from: expense.date))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(text: expense.status.rawValue, color: statusColor(expense.status))
                        }

                        Divider()

                        DetailRow(label: "Item", value: expense.itemName)
                        DetailRow(label: "Supplier", value: expense.supplier)
                        DetailRow(label: "Amount", value: Formatters.formatCents(expense.amountCents))
                        DetailRow(label: "Reference", value: expense.reference.isEmpty ? "—" : expense.reference)
                        DetailRow(label: "Category", value: expense.category)
                        if !expense.remark.isEmpty {
                            DetailRow(label: "Remark", value: expense.remark)
                        }
                        if let claimNumber = expense.claim?.claimNumber {
                            DetailRow(label: "Claim", value: claimNumber)
                        }

                        // Document attachment
                        if let filename = expense.documentFilename {
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Attachment")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button {
                                    NSWorkspace.shared.open(DocumentStore.url(for: filename))
                                } label: {
                                    Label(filename.components(separatedBy: "_").dropFirst().joined(separator: "_"),
                                          systemImage: "paperclip")
                                }
                                .buttonStyle(.link)
                            }
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
                    ExpenseFormView(mode: .edit(expense))
                }
                .confirmationDialog("Delete Expense?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { deleteExpense(expense) }
                } message: {
                    Text("This will permanently delete the expense and its attachment.")
                }
            } else {
                ContentUnavailableView("Expense Not Found", systemImage: "doc.text")
            }
        }
        .navigationTitle(expense?.itemName ?? "Expense")
    }

    private func statusColor(_ status: ExpenseStatus) -> Color {
        switch status {
        case .unpaid: return .red
        case .paid: return .green
        }
    }

    private func deleteExpense(_ expense: Expense) {
        if let filename = expense.documentFilename {
            DocumentStore.deleteFile(named: filename)
        }
        nav.selectedExpenseID = nil
        modelContext.delete(expense)
    }
}
