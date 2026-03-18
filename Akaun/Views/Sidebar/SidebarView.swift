import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(AppNavigationModel.self) private var nav

    @Query private var allExpenses: [Expense]
    @Query private var allClaims: [Claim]

    private var unpaidCount: Int { allExpenses.filter { $0.status == .unpaid }.count }
    private var pendingCount: Int { allClaims.filter { $0.status == .pending }.count }

    var body: some View {
        @Bindable var nav = nav
        List(selection: $nav.selectedSection) {
            Label("Dashboard", systemImage: "square.grid.2x2")
                .tag(SidebarSection.dashboard)

            Label("Expenses", systemImage: "doc.text")
                .badge(unpaidCount)
                .tag(SidebarSection.expenses)

            Label("Income", systemImage: "banknote")
                .tag(SidebarSection.income)

            Label("Claims", systemImage: "list.bullet.clipboard")
                .badge(pendingCount)
                .tag(SidebarSection.claims)

            Label("Auto Import", systemImage: "tray.and.arrow.down")
                .tag(SidebarSection.autoImport)
        }
        .listStyle(.sidebar)
    }
}
