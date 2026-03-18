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
    @State private var status = ExpenseStatus.unpaid
    @State private var remark = ""
    @State private var documentFilename: String?

    @State private var category = "Other"

    @State private var showingFilePicker = false
    @State private var fileImportError: String?
    @State private var isDragTargeted = false

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Item Name", text: $itemName)
                    TextField("Supplier", text: $supplier)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Amount (RM)", text: $amountString)
                        .onChange(of: amountString) { _, new in
                            amountString = sanitiseAmount(new)
                        }
                    TextField("Reference", text: $reference)
                    Picker("Category", selection: $category) {
                        ForEach(loadCategories(), id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Status") {
                    Picker("Status", selection: $status) {
                        Text("Unpaid").tag(ExpenseStatus.unpaid)
                        Text("Paid").tag(ExpenseStatus.paid)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Remark") {
                    TextEditor(text: $remark)
                        .frame(minHeight: 60)
                }

                Section("Attachment") {
                    if let filename = documentFilename {
                        let displayName = filename.components(separatedBy: "_").dropFirst().joined(separator: "_")
                        HStack {
                            Label(displayName, systemImage: "paperclip")
                            Spacer()
                            Button("Remove", role: .destructive) {
                                if case .edit(let expense) = mode, expense.documentFilename == filename {
                                    DocumentStore.deleteFile(named: filename)
                                }
                                documentFilename = nil
                            }
                            .buttonStyle(.borderless)
                        }
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    isDragTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                                )
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isDragTargeted ? Color.accentColor.opacity(0.06) : Color.clear)
                                )
                            VStack(spacing: 6) {
                                Image(systemName: "arrow.down.doc")
                                    .font(.title2)
                                    .foregroundStyle(isDragTargeted ? Color.accentColor : Color.secondary)
                                Text("Drop file here")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                                Button("Browse…") { showingFilePicker = true }
                                    .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 16)
                        }
                        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                            guard let provider = providers.first else { return false }
                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                                guard let data = item as? Data,
                                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                                DispatchQueue.main.async { attachURL(url) }
                            }
                            return true
                        }
                    }
                    if let error = fileImportError {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEdit ? "Edit Expense" : "New Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(itemName.isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    attachURL(url)
                case .failure(let error):
                    fileImportError = error.localizedDescription
                }
            }
        }
        .onAppear { populateIfEditing() }
        .frame(minWidth: 480, minHeight: 500)
    }

    private func attachURL(_ url: URL) {
        do {
            let filename = try DocumentStore.importFile(from: url)
            documentFilename = filename
            fileImportError = nil
        } catch {
            fileImportError = "Could not attach file: \(error.localizedDescription)"
        }
    }

    private func populateIfEditing() {
        guard case .edit(let expense) = mode else { return }
        itemName = expense.itemName
        supplier = expense.supplier
        date = expense.date
        amountString = String(format: "%.2f", Double(expense.amountCents) / 100.0)
        reference = expense.reference
        status = expense.status
        remark = expense.remark
        category = expense.category
        documentFilename = expense.documentFilename
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
                status: status,
                documentFilename: documentFilename,
                remark: remark,
                category: category
            )
            modelContext.insert(expense)
            try? modelContext.save()
        case .edit(let expense):
            expense.itemName = itemName
            expense.supplier = supplier
            expense.date = date
            expense.amountCents = cents
            expense.reference = reference
            expense.status = status
            expense.documentFilename = documentFilename
            expense.remark = remark
            expense.category = category
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
