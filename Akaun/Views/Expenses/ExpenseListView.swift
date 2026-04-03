import SwiftUI
import SwiftData

struct ExpenseListView: View {
    @Environment(AppNavigationModel.self) private var nav
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    @State private var showingForm = false
    @State private var deleteTarget: Expense?
    @State private var searchText: String = ""
    @State private var debouncedQuery: String = ""

    private var filteredExpenses: [Expense] {
        let query = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return expenses }
        let lower = query.lowercased()
        return expenses.filter { expense in
            expense.expenseNumber.lowercased().contains(lower) ||
            expense.itemName.lowercased().contains(lower) ||
            expense.supplier.lowercased().contains(lower) ||
            expense.reference.lowercased().contains(lower) ||
            expense.remark.lowercased().contains(lower) ||
            expense.category.lowercased().contains(lower) ||
            (expense.searchData?.text.lowercased().contains(lower) ?? false)
        }
    }

    var body: some View {
        @Bindable var nav = nav
        List(selection: $nav.selectedExpenseID) {
            ForEach(filteredExpenses) { expense in
                ExpenseRowView(expense: expense)
                    .tag(expense.persistentModelID)
            }
        }
        .navigationTitle("Expenses")
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search expenses")
        .onChange(of: searchText) { _, new in
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if searchText == new { debouncedQuery = new }
            }
        }
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
