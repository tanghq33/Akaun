import SwiftUI
import SwiftData

struct IncomeListView: View {
    @Environment(AppNavigationModel.self) private var nav
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]

    @State private var showingForm = false

    var body: some View {
        @Bindable var nav = nav
        List(selection: $nav.selectedIncomeID) {
            ForEach(incomes) { income in
                IncomeRowView(income: income)
                    .tag(income.persistentModelID)
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
    }
}
