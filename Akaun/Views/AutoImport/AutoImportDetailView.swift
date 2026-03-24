import SwiftUI
import SwiftData

struct AutoImportDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AutoImportQueue.self) private var queue

    var body: some View {
        Group {
            if queue.reviewItems.isEmpty {
                ContentUnavailableView("No Receipts Ready", systemImage: "doc.text.magnifyingglass")
            } else {
                List {
                    ForEach(queue.reviewItems) { item in
                        AutoImportReviewRowView(item: item)
                            .listRowSeparator(.visible)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Review")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Import All") { importAllClean() }
                    .disabled(!queue.reviewItems.contains {
                        $0.state == .ready && !$0.isSkipped
                            && ($0.duplicateMatches ?? []).isEmpty
                    })
            }
            ToolbarItem {
                Button("Clear Completed") { queue.clearCompleted() }
                    .disabled(!queue.reviewItems.contains { $0.state == .imported })
            }
        }
        .onChange(of: queue.items.filter { $0.state == .ready && $0.duplicateMatches == nil }.map(\.id)) { _, newValue in
            if !newValue.isEmpty { runAutoCheck() }
        }
    }

    /// Import only items that have no duplicates and are not skipped.
    private func importAllClean() {
        let clean = queue.reviewItems.filter {
            $0.state == .ready && !$0.isSkipped && ($0.duplicateMatches ?? []).isEmpty
        }
        for item in clean { queue.importItem(item, in: modelContext) }
    }

    /// Populate duplicateMatches for any unchecked ready items.
    private func runAutoCheck() {
        let unchecked = queue.reviewItems.filter { $0.state == .ready && $0.duplicateMatches == nil }
        guard !unchecked.isEmpty else { return }

        let expenses = (try? modelContext.fetch(FetchDescriptor<Expense>())) ?? []
        let incomes  = (try? modelContext.fetch(FetchDescriptor<Income>())) ?? []

        for item in unchecked {
            item.duplicateMatches = DuplicateDetector.findMatches(
                for: item, expenses: expenses, incomes: incomes)
        }
    }
}
