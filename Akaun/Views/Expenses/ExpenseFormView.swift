import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ExpenseFormView: View {
    enum Mode {
        case create
        case edit(Expense)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var itemName = ""
    @State private var supplier = ""
    @State private var date = Date.now
    @State private var amountString = ""
    @State private var reference = ""
    @State private var remark = ""

    @State private var category = "Other"

    @State private var attachments: [AttachmentItem] = []
    @State private var existingFilenames: Set<String> = []
    @State private var newFilenames: Set<String> = []

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    @AppStorage("godMode.enabled") private var godModeEnabled = false

    /// True when the expense's status or claim relationship warrants a lock.
    private var needsLock: Bool {
        if case .edit(let expense) = mode {
            return expense.status == .pending || expense.status == .paid || expense.claim != nil
        }
        return false
    }

    /// Descriptive fields are editable in god mode even when locked.
    private var isLocked: Bool { needsLock && !godModeEnabled }

    /// Amount always stays locked when needsLock is true — it feeds Claim.totalAmountCents.
    private var isAmountLocked: Bool { needsLock }

    private var lockMessage: String {
        if case .edit(let expense) = mode {
            if expense.claim != nil {
                return "This expense is part of claim \(expense.claim!.claimNumber). Enable God Mode in Settings → Advanced to edit descriptive fields."
            }
            return "This expense is \(expense.status.rawValue.lowercased()) and cannot be fully edited. Enable God Mode in Settings → Advanced to edit descriptive fields."
        }
        return ""
    }

    var body: some View {
        NavigationStack {
            Form {
                if needsLock {
                    Section {
                        if godModeEnabled {
                            Label("God Mode active — amount is still locked", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Text(lockMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Details") {
                    TextField("Item Name", text: $itemName)
                        .disabled(isLocked)
                    TextField("Supplier", text: $supplier)
                        .disabled(isLocked)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .disabled(isLocked)
                    TextField("Amount (RM)", text: $amountString)
                        .disabled(isAmountLocked)
                        .onChange(of: amountString) { _, new in
                            amountString = sanitiseAmount(new)
                        }
                    TextField("Reference", text: $reference)
                        .disabled(isLocked)
                    Picker("Category", selection: $category) {
                        ForEach(loadCategories(), id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Remark") {
                    TextEditor(text: $remark)
                        .frame(minHeight: 60)
                        .disabled(isLocked)
                }

                if !isLocked {
                    AttachmentSectionView(
                        subfolder: "Expenses",
                        attachments: $attachments,
                        existingFilenames: existingFilenames,
                        newFilenames: $newFilenames
                    )
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEdit ? "Edit Expense" : "New Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancelAndCleanup() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(itemName.isEmpty)
                }
            }
        }
        .onAppear { populateIfEditing() }
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK") {}
        } message: {
            Text(saveErrorMessage)
        }
        .frame(minWidth: 480, minHeight: 500)
    }

    private func populateIfEditing() {
        guard case .edit(let expense) = mode else { return }
        itemName = expense.itemName
        supplier = expense.supplier
        date = expense.date
        amountString = String(format: "%.2f", Double(expense.amountCents) / 100.0)
        reference = expense.reference
        remark = expense.remark
        category = expense.category

        if !expense.attachments.isEmpty {
            attachments = expense.attachments.map { AttachmentItem(filename: $0.filename, displayName: $0.displayName) }
            existingFilenames = Set(expense.attachments.map { $0.filename })
        } else if let legacy = expense.documentFilename, !legacy.isEmpty {
            let display = DocumentStore.displayName(for: legacy)
            attachments = [AttachmentItem(filename: legacy, displayName: display)]
            existingFilenames = [legacy]
        }
    }

    private func save() {
        let cents = parseCents(amountString)
        switch mode {
        case .create:
            let expense = Expense(
                expenseNumber: RunningNumberGenerator.next(prefix: "EX", for: date, in: modelContext),
                itemName: itemName,
                supplier: supplier,
                date: date,
                amountCents: cents,
                reference: reference,
                status: .unpaid,
                remark: remark,
                category: category
            )
            modelContext.insert(expense)
            for item in attachments {
                let att = Attachment(filename: item.filename, displayName: item.displayName)
                expense.attachments.append(att)
            }
            do {
                try modelContext.save()
            } catch {
                saveErrorMessage = error.localizedDescription
                showSaveError = true
                return
            }
            if !attachments.isEmpty {
                let ctx = modelContext
                Task { await extractAndStoreSearchText(for: expense, in: ctx) }
            }

        case .edit(let expense):
            expense.category = category             // always writable

            if !isAmountLocked {
                expense.amountCents = cents
            }

            if !isLocked {
                expense.itemName = itemName
                expense.supplier = supplier
                expense.date = date
                expense.reference = reference
                expense.remark = remark

                // Diff attachments
                let currentFilenames = Set(attachments.map { $0.filename })
                for existing in expense.attachments where !currentFilenames.contains(existing.filename) {
                    modelContext.delete(existing)
                }
                let existingModelFilenames = Set(expense.attachments.map { $0.filename })
                for item in attachments where !existingModelFilenames.contains(item.filename) {
                    let att = Attachment(filename: item.filename, displayName: item.displayName)
                    expense.attachments.append(att)
                }
                expense.documentFilename = nil
            }
            if !expense.attachments.isEmpty {
                try? modelContext.save()
                let ctx = modelContext
                Task { await extractAndStoreSearchText(for: expense, in: ctx) }
            }
        }
        dismiss()
    }

    private func cancelAndCleanup() {
        for filename in newFilenames {
            DocumentStore.deleteFile(named: filename)
        }
        dismiss()
    }

    private func sanitiseAmount(_ input: String) -> String {
        var result = ""
        var hasDot = false
        var decimalCount = 0
        for ch in input {
            if ch.isNumber {
                if hasDot {
                    if decimalCount < 2 {
                        result.append(ch)
                        decimalCount += 1
                    }
                } else {
                    result.append(ch)
                }
            } else if ch == "." && !hasDot {
                hasDot = true
                result.append(ch)
            }
        }
        return result
    }

    private func parseCents(_ string: String) -> Int {
        let value = Double(string) ?? 0.0
        return Int((value * 100).rounded())
    }
}
