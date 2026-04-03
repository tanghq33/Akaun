import SwiftUI
import SwiftData

struct IncomeListView: View {
    @Environment(AppNavigationModel.self) private var nav
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]

    @State private var showingForm = false
    @State private var deleteTarget: Income?
    @State private var searchText: String = ""
    @State private var debouncedQuery: String = ""
    @State private var debounceTask: Task<Void, Never>?

    private var filteredIncomes: [Income] {
        let query = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return incomes }
        let lower = query.lowercased()
        return incomes.filter { income in
            income.incomeNumber.lowercased().contains(lower) ||
            income.source.lowercased().contains(lower) ||
            income.descriptionText.lowercased().contains(lower) ||
            income.reference.lowercased().contains(lower) ||
            income.category.lowercased().contains(lower) ||
            income.remark.lowercased().contains(lower) ||
            (income.searchData?.text.lowercased().contains(lower) ?? false)
        }
    }

    var body: some View {
        @Bindable var nav = nav
        List(selection: $nav.selectedIncomeID) {
            ForEach(filteredIncomes) { income in
                IncomeRowView(income: income)
                    .tag(income.persistentModelID)
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteTarget = income
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .navigationTitle("Income")
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search income")
        .onChange(of: searchText) { _, new in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if !Task.isCancelled { debouncedQuery = new }
            }
        }
        .onChange(of: debouncedQuery) { _, _ in
            if let selectedID = nav.selectedIncomeID,
               !filteredIncomes.contains(where: { $0.persistentModelID == selectedID }) {
                nav.selectedIncomeID = nil
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingForm = true } label: {
                    Label("New Income", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingForm) {
            IncomeFormView(mode: .create)
        }
        .confirmationDialog("Delete Income?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let income = deleteTarget {
                    deleteIncome(income)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func deleteIncome(_ income: Income) {
        if nav.selectedIncomeID == income.persistentModelID {
            nav.selectedIncomeID = nil
        }
        for attachment in income.attachments {
            DocumentStore.deleteFile(named: attachment.filename)
        }
        modelContext.delete(income)
        try? modelContext.save()
        deleteTarget = nil
    }
}
