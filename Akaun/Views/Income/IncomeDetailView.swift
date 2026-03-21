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

                        if !income.descriptionText.isEmpty {
                            DetailRow(label: "Description", value: income.descriptionText)
                        }
                        if !income.source.isEmpty {
                            DetailRow(label: "Source", value: income.source)
                        }
                        if !income.reference.isEmpty {
                            DetailRow(label: "Reference", value: income.reference)
                        }
                        if !income.category.isEmpty {
                            DetailRow(label: "Category", value: income.category)
                        }
                        if !income.remark.isEmpty {
                            DetailRow(label: "Remark", value: income.remark)
                        }

                        IncomeAttachmentListView(attachments: income.attachments)
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
                        deleteIncome(income)
                    }
                }
            } else {
                ContentUnavailableView("Income Not Found", systemImage: "banknote")
            }
        }
        .navigationTitle(income.flatMap { $0.descriptionText.isEmpty ? nil : $0.descriptionText } ?? income?.incomeNumber ?? "Income")
    }

    private func deleteIncome(_ income: Income) {
        nav.selectedIncomeID = nil
        for attachment in income.attachments {
            DocumentStore.deleteFile(named: attachment.filename)
        }
        modelContext.delete(income)
    }
}

private struct IncomeAttachmentListView: View {
    let attachments: [IncomeAttachment]

    @State private var quickLookCoordinator = QuickLookCoordinator()

    var body: some View {
        if !attachments.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(attachments.count == 1 ? "Attachment" : "Attachments (\(attachments.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(attachments.enumerated()), id: \.element.filename) { index, attachment in
                    Button {
                        let urls = attachments.map { DocumentStore.url(for: $0.filename) }
                        quickLookCoordinator.show(urls: urls, at: index)
                    } label: {
                        Label(attachment.displayName, systemImage: "paperclip")
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
}
