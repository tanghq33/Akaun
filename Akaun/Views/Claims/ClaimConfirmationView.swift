import SwiftUI
import SwiftData

struct ClaimConfirmationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let claim: Claim

    @State private var attachments: [AttachmentItem] = []
    @State private var newFilenames: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Claim Summary") {
                    LabeledContent("Claim", value: claim.claimNumber)
                    LabeledContent("Date", value: Formatters.displayDate.string(from: claim.date))
                    LabeledContent("Total", value: Formatters.formatCents(claim.totalAmountCents))
                    LabeledContent("Expenses", value: "\(claim.expenses.count)")
                }

                AttachmentSectionView(
                    subfolder: "Claims",
                    attachments: $attachments,
                    existingFilenames: [],
                    newFilenames: $newFilenames
                )
            }
            .formStyle(.grouped)
            .navigationTitle("Confirm Claim")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancelAndCleanup() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { confirm() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 400)
    }

    private func confirm() {
        claim.status = .done

        for expense in claim.expenses {
            expense.status = .paid
        }

        for item in attachments {
            let att = ClaimAttachment(filename: item.filename, displayName: item.displayName)
            claim.claimAttachments.append(att)
        }

        try? modelContext.save()
        dismiss()
    }

    private func cancelAndCleanup() {
        for filename in newFilenames {
            DocumentStore.deleteFile(named: filename)
        }
        dismiss()
    }
}
