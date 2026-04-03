import SwiftUI
import SwiftData

struct ClaimListView: View {
    @Environment(AppNavigationModel.self) private var nav
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Claim.date, order: .reverse) private var claims: [Claim]

    @State private var showingForm = false
    @State private var searchText: String = ""
    @State private var debouncedQuery: String = ""
    @State private var debounceTask: Task<Void, Never>?

    private var filteredClaims: [Claim] {
        let query = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return claims }
        let lower = query.lowercased()
        return claims.filter { claim in
            claim.claimNumber.lowercased().contains(lower) ||
            (claim.searchData?.text.lowercased().contains(lower) ?? false)
        }
    }

    var body: some View {
        @Bindable var nav = nav
        List(selection: $nav.selectedClaimID) {
            ForEach(filteredClaims) { claim in
                ClaimRowView(claim: claim)
                    .tag(claim.persistentModelID)
            }
        }
        .navigationTitle("Claims")
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search claims")
        .onChange(of: searchText) { _, new in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if !Task.isCancelled { debouncedQuery = new }
            }
        }
        .onChange(of: debouncedQuery) { _, _ in
            if let selectedID = nav.selectedClaimID,
               !filteredClaims.contains(where: { $0.persistentModelID == selectedID }) {
                nav.selectedClaimID = nil
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingForm = true } label: {
                    Label("New Claim", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingForm) {
            ClaimFormView()
        }
    }
}
