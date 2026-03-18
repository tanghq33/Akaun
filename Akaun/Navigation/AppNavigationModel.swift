import SwiftData
import Observation

enum SidebarSection: String, Hashable, CaseIterable {
    case dashboard = "Dashboard"
    case expenses = "Expenses"
    case income = "Income"
    case claims = "Claims"
    case autoImport = "Auto Import"
}

@Observable final class AppNavigationModel {
    var selectedSection: SidebarSection? = .dashboard
    var selectedExpenseID: PersistentIdentifier?
    var selectedIncomeID: PersistentIdentifier?
    var selectedClaimID: PersistentIdentifier?
}
