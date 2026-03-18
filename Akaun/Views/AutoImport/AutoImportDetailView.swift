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
                Button("Import All") {
                    queue.importAllReady(in: modelContext)
                }
                .disabled(!queue.reviewItems.contains { $0.state == .ready })
            }
            ToolbarItem {
                Button("Clear Completed") {
                    queue.clearCompleted()
                }
                .disabled(!queue.reviewItems.contains { $0.state == .imported })
            }
        }
    }
}
