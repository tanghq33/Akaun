import SwiftUI
import SwiftData

struct ClaimFormView: View {
    enum Mode {
        case create
        case edit(Claim)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var date = Date.now
    @State private var status = ClaimStatus.pending
    @State private var selectedExpenseIDs: Set<PersistentIdentifier> = []

    // All self-paid expenses with no claim linked
    @Query(sort: \Expense.date, order: .reverse)
    private var allExpenses: [Expense]

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// Self-paid expenses that have no claim, plus those already linked to the claim being edited.
    private var availableExpenses: [Expense] {
        if case .edit(let claim) = mode {
            let linkedIDs = Set(claim.expenses.map { $0.persistentModelID })
            return allExpenses.filter {
                $0.status == .unpaid && ($0.claim == nil || linkedIDs.contains($0.persistentModelID))
            }
        }
        return allExpenses.filter { $0.status == .unpaid && $0.claim == nil }
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
                    if isEdit {
                        Picker("Status", selection: $status) {
                            ForEach(ClaimStatus.allCases, id: \.self) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
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
            }
            .formStyle(.grouped)
            .navigationTitle(isEdit ? "Edit Claim" : "New Claim")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .onAppear { populateIfEditing() }
        .frame(minWidth: 500, minHeight: 500)
    }

    private func populateIfEditing() {
        guard case .edit(let claim) = mode else { return }
        date = claim.date
        status = claim.status
        selectedExpenseIDs = Set(claim.expenses.map { $0.persistentModelID })
    }

    private func save() {
        let selectedExpenses = availableExpenses.filter { selectedExpenseIDs.contains($0.persistentModelID) }

        switch mode {
        case .create:
            let claim = Claim(
                claimNumber: RunningNumberGenerator.next(prefix: "CL", for: date, in: modelContext),
                date: date,
                status: .pending
            )
            modelContext.insert(claim)
            claim.expenses = selectedExpenses
            try? modelContext.save()

        case .edit(let claim):
            claim.date = date
            claim.status = status
            // Unlink expenses that were removed from the selection
            for expense in claim.expenses where !selectedExpenseIDs.contains(expense.persistentModelID) {
                expense.claim = nil
            }
            claim.expenses = selectedExpenses
        }
        dismiss()
    }
}
