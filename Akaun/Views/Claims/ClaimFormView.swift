import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ClaimFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date.now
    @State private var selectedExpenseIDs: Set<PersistentIdentifier> = []

    @State private var attachments: [AttachmentItem] = []
    @State private var newFilenames: Set<String> = []
    @State private var markAsPaid = false

    @Query(sort: \Expense.date, order: .reverse)
    private var allExpenses: [Expense]

    private var availableExpenses: [Expense] {
        allExpenses.filter { $0.status == .unpaid && $0.claim == nil }
    }

    private var selectedTotal: Int {
        availableExpenses
            .filter { selectedExpenseIDs.contains($0.persistentModelID) }
            .reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section {
                    if availableExpenses.isEmpty {
                        Text("No eligible expenses (Unpaid, not yet in a claim).")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(availableExpenses) { expense in
                            HStack {
                                Image(systemName: selectedExpenseIDs.contains(expense.persistentModelID)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedExpenseIDs.contains(expense.persistentModelID)
                                                     ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading) {
                                    Text(expense.itemName.isEmpty ? "Unnamed" : expense.itemName)
                                    Text(expense.expenseNumber + " · " + Formatters.displayDate.string(from: expense.date))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Formatters.formatCents(expense.amountCents))
                                    .font(.subheadline)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedExpenseIDs.contains(expense.persistentModelID) {
                                    selectedExpenseIDs.remove(expense.persistentModelID)
                                } else {
                                    selectedExpenseIDs.insert(expense.persistentModelID)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Expenses")
                        Spacer()
                        if !selectedExpenseIDs.isEmpty {
                            Text("Total: \(Formatters.formatCents(selectedTotal))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                AttachmentSectionView(
                    attachments: $attachments,
                    existingFilenames: [],
                    newFilenames: $newFilenames
                )

                Section {
                    Toggle("Mark as Paid", isOn: $markAsPaid)
                        .disabled(attachments.isEmpty)
                }
            }
            .onChange(of: attachments.count) { oldCount, newCount in
                if oldCount == 0 && newCount > 0 {
                    markAsPaid = true
                } else if newCount == 0 {
                    markAsPaid = false
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Claim")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancelAndCleanup() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(selectedExpenseIDs.isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 500)
    }

    private func save() {
        let selectedExpenses = availableExpenses.filter { selectedExpenseIDs.contains($0.persistentModelID) }

        let claimStatus: ClaimStatus = markAsPaid ? .done : .pending
        let expenseStatus: ExpenseStatus = markAsPaid ? .paid : .pending

        let claim = Claim(
            claimNumber: RunningNumberGenerator.next(prefix: "CL", for: date, in: modelContext),
            date: date,
            status: claimStatus
        )
        modelContext.insert(claim)
        claim.expenses = selectedExpenses

        for expense in selectedExpenses {
            expense.status = expenseStatus
        }

        for item in attachments {
            let att = Attachment(filename: item.filename, displayName: item.displayName)
            claim.attachments.append(att)
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
