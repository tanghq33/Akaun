import SwiftUI
import SwiftData

struct ExpenseListView: View {
    @Environment(AppNavigationModel.self) private var nav
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    @State private var showingForm = false
    @State private var deleteTarget: Expense?

    var body: some View {
        @Bindable var nav = nav
        List(selection: $nav.selectedExpenseID) {
            ForEach(expenses) { expense in
                ExpenseRowView(expense: expense)
                    .tag(expense.persistentModelID)
            }
        }
        .navigationTitle("Expenses")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingForm = true } label: {
                    Label("New Expense", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingForm) {
            ExpenseFormView(mode: .create)
        }
        .confirmationDialog(
            "Delete Expense",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let expense = deleteTarget {
                    deleteExpense(expense)
                }
            }
        } message: {
            Text("This will permanently delete the expense and its attachments.")
        }
    }

    private func deleteExpense(_ expense: Expense) {
        guard expense.claim == nil else { return }
        DocumentStore.deleteFiles(for: expense.attachments)
        if let legacy = expense.documentFilename {
            DocumentStore.deleteFile(named: legacy)
        }
        if nav.selectedExpenseID == expense.persistentModelID {
            nav.selectedExpenseID = nil
        }
        modelContext.delete(expense)
    }
}
