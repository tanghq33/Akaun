import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppNavigationModel.self) private var nav

    var body: some View {
        @Bindable var nav = nav
        if nav.selectedSection == .dashboard {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
            } detail: {
                DashboardView()
            }
        } else {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
            } content: {
                Group {
                    switch nav.selectedSection {
                    case .expenses:
                        ExpenseListView()
                    case .income:
                        IncomeListView()
                    case .claims:
                        ClaimListView()
                    case .autoImport:
                        AutoImportView()
                    case .dashboard, nil:
                        ContentUnavailableView("Select a Section", systemImage: "sidebar.left")
                    }
                }
                .navigationSplitViewColumnWidth(ideal: 380)
            } detail: {
                switch nav.selectedSection {
                case .expenses:
                    if let id = nav.selectedExpenseID {
                        ExpenseDetailView(expenseID: id)
                    } else {
                        ContentUnavailableView("No Expense Selected", systemImage: "doc.text")
                    }
                case .income:
                    if let id = nav.selectedIncomeID {
                        IncomeDetailView(incomeID: id)
                    } else {
                        ContentUnavailableView("No Income Selected", systemImage: "banknote")
                    }
                case .claims:
                    if let id = nav.selectedClaimID {
                        ClaimDetailView(claimID: id)
                    } else {
                        ContentUnavailableView("No Claim Selected", systemImage: "list.bullet.clipboard")
                    }
                case .autoImport:
                    AutoImportDetailView()
                case .dashboard, nil:
                    ContentUnavailableView("Select a Section", systemImage: "sidebar.left")
                }
            }
        }
    }
}
