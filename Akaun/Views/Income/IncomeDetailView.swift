import SwiftUI
import SwiftData

struct IncomeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigationModel.self) private var nav

    let incomeID: PersistentIdentifier

    @State private var showingEditForm = false
    @State private var showingDeleteConfirm = false

    private var income: Income? {
        modelContext.model(for: incomeID) as? Income
    }

    var body: some View {
        Group {
            if let income {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(income.incomeNumber)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text(Formatters.displayDate.string(from: income.date))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Formatters.formatCents(income.amountCents))
                                .font(.title)
                                .foregroundStyle(.green)
                        }

                        Divider()

                        if !income.remark.isEmpty {
                            DetailRow(label: "Remark", value: income.remark)
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
                    IncomeFormView(mode: .edit(income))
                }
                .confirmationDialog("Delete Income?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        nav.selectedIncomeID = nil
                        modelContext.delete(income)
                    }
                }
            } else {
                ContentUnavailableView("Income Not Found", systemImage: "banknote")
            }
        }
        .navigationTitle(income?.incomeNumber ?? "Income")
    }
}
