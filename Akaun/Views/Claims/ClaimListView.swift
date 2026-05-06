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
            // H5: cleaner debounce — cancellation throws, assignment skipped
            debounceTask = Task {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                debouncedQuery = new
            }
        }
        // H4: extracted to match ExpenseListView pattern
        .onChange(of: debouncedQuery) { _, _ in
            clearSelectionIfNeeded()
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

    // H4: extracted helper (was inlined)
    private func clearSelectionIfNeeded() {
        if let selectedID = nav.selectedClaimID,
           !filteredClaims.contains(where: { $0.persistentModelID == selectedID }) {
            nav.selectedClaimID = nil
        }
    }
}
