import SwiftUI
import SwiftData

struct ExpenseListView: View {
    @Environment(AppNavigationModel.self) private var nav
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    @State private var showingForm = false
    @State private var showingFilter = false
    @State private var deleteTarget: Expense?
    @State private var searchText: String = ""
    @State private var debouncedQuery: String = ""
    @State private var debounceTask: Task<Void, Never>?

    private var filteredExpenses: [Expense] {
        var result = expenses

        let query = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            let lower = query.lowercased()
            result = result.filter { expense in
                expense.expenseNumber.lowercased().contains(lower) ||
                expense.itemName.lowercased().contains(lower) ||
                expense.supplier.lowercased().contains(lower) ||
                expense.reference.lowercased().contains(lower) ||
                expense.remark.lowercased().contains(lower) ||
                expense.category.lowercased().contains(lower) ||
                (expense.searchData?.text.lowercased().contains(lower) ?? false)
            }
        }

        let filter = nav.expenseFilter

        if !filter.statuses.isEmpty {
            result = result.filter { filter.statuses.contains($0.status) }
        }
        if !filter.categories.isEmpty {
            result = result.filter { filter.categories.contains($0.category) }
        }
        // H1: normalise dateFrom to start-of-day so morning entries aren't excluded
        if let from = filter.dateFrom {
            let startOfDay = Calendar.current.startOfDay(for: from)
            result = result.filter { $0.date >= startOfDay }
        }
        // H1: remove force-unwrap
        if let to = filter.dateTo,
           let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: to) {
            result = result.filter { $0.date < endOfDay }
        }
        if let min = filter.amountMinCents {
            result = result.filter { $0.amountCents >= min }
        }
        if let max = filter.amountMaxCents {
            result = result.filter { $0.amountCents <= max }
        }

        return result
    }

    var body: some View {
        @Bindable var nav = nav
        List(selection: $nav.selectedExpenseID) {
            ForEach(filteredExpenses) { expense in
                ExpenseRowView(expense: expense)
                    .tag(expense.persistentModelID)
                    // M4: wire up deleteTarget via context menu
                    .contextMenu {
                        if expense.claim == nil {
                            Button(role: .destructive) {
                                deleteTarget = expense
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
            }
        }
        .navigationTitle("Expenses")
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search expenses")
        .onChange(of: searchText) { _, new in
            debounceTask?.cancel()
            // H5: let cancellation throw and skip the assignment naturally
            debounceTask = Task {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                debouncedQuery = new
            }
        }
        .onChange(of: debouncedQuery) { _, _ in
            clearSelectionIfNeeded()
        }
        .onChange(of: nav.expenseFilter) { _, _ in
            clearSelectionIfNeeded()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingForm = true } label: {
                    Label("New Expense", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button { showingFilter.toggle() } label: {
                    Label("Filter", systemImage: nav.expenseFilter.isActive
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle")
                }
                .popover(isPresented: $showingFilter) {
                    ExpenseFilterView(filter: $nav.expenseFilter)
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
            // M3: add Cancel button to match IncomeListView
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the expense and its attachments.")
        }
    }

    private func clearSelectionIfNeeded() {
        if let selectedID = nav.selectedExpenseID,
           !filteredExpenses.contains(where: { $0.persistentModelID == selectedID }) {
            nav.selectedExpenseID = nil
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
        try? modelContext.save()
    }
}
