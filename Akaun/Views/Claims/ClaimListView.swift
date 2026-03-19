import SwiftUI
import SwiftData

struct ClaimListView: View {
    @Environment(AppNavigationModel.self) private var nav
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Claim.date, order: .reverse) private var claims: [Claim]

    @State private var showingForm = false

    var body: some View {
        @Bindable var nav = nav
        List(selection: $nav.selectedClaimID) {
            ForEach(claims) { claim in
                ClaimRowView(claim: claim)
                    .tag(claim.persistentModelID)
            }
        }
        .navigationTitle("Claims")
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
