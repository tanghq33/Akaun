import SwiftUI
import SwiftData

struct IncomeListView: View {
    @Environment(AppNavigationModel.self) private var nav
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]

    @State private var showingForm = false
    @State private var deleteTarget: Income?

    var body: some View {
        @Bindable var nav = nav
        List(selection: $nav.selectedIncomeID) {
            ForEach(incomes) { income in
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
        deleteTarget = nil
    }
}
