import SwiftUI
import SwiftData

struct IncomeFormView: View {
    enum Mode {
        case create
        case edit(Income)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var source = ""
    @State private var descriptionText = ""
    @State private var date = Date.now
    @State private var amountString = ""
    @State private var reference = ""
    @State private var category = "Other"
    @State private var remark = ""

    @State private var attachments: [AttachmentItem] = []
    @State private var existingFilenames: Set<String> = []
    @State private var newFilenames: Set<String> = []

    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Description", text: $descriptionText)
                    TextField("Source", text: $source)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Amount (RM)", text: $amountString)
                        .onChange(of: amountString) { _, new in
                            amountString = sanitiseAmount(new)
                        }
                    TextField("Reference", text: $reference)
                    Picker("Category", selection: $category) {
                        ForEach(loadIncomeCategories(), id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Remark") {
                    TextEditor(text: $remark)
                        .frame(minHeight: 60)
                }

                AttachmentSectionView(
                    subfolder: "Income",
                    attachments: $attachments,
                    existingFilenames: existingFilenames,
                    newFilenames: $newFilenames
                )
            }
            .formStyle(.grouped)
            .navigationTitle(isEdit ? "Edit Income" : "New Income")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancelAndCleanup() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(descriptionText.isEmpty)
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
        guard case .edit(let income) = mode else { return }
        source = income.source
        descriptionText = income.descriptionText
        date = income.date
        amountString = String(format: "%.2f", Double(income.amountCents) / 100.0)
        reference = income.reference
        category = income.category
        remark = income.remark

        if !income.attachments.isEmpty {
            attachments = income.attachments.map { AttachmentItem(filename: $0.filename, displayName: $0.displayName) }
            existingFilenames = Set(income.attachments.map { $0.filename })
        }
    }

    private func save() {
        let cents = parseCents(amountString)
        switch mode {
        case .create:
            let income = Income(
                incomeNumber: RunningNumberGenerator.next(prefix: "IN", for: date, in: modelContext),
                source: source,
                descriptionText: descriptionText,
                date: date,
                amountCents: cents,
                reference: reference,
                category: category,
                remark: remark
            )
            modelContext.insert(income)
            for item in attachments {
                let att = IncomeAttachment(filename: item.filename, displayName: item.displayName)
                income.attachments.append(att)
            }
            do {
                try modelContext.save()
            } catch {
                saveErrorMessage = error.localizedDescription
                showSaveError = true
                return
            }

        case .edit(let income):
            income.source = source
            income.descriptionText = descriptionText
            income.date = date
            income.amountCents = cents
            income.reference = reference
            income.category = category
            income.remark = remark

            // Diff attachments
            let currentFilenames = Set(attachments.map { $0.filename })
            for existing in income.attachments where !currentFilenames.contains(existing.filename) {
                modelContext.delete(existing)
            }
            let existingModelFilenames = Set(income.attachments.map { $0.filename })
            for item in attachments where !existingModelFilenames.contains(item.filename) {
                let att = IncomeAttachment(filename: item.filename, displayName: item.displayName)
                income.attachments.append(att)
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
