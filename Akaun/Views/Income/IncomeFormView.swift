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

    @State private var date = Date.now
    @State private var amountString = ""
    @State private var remark = ""

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var amountCents: Int {
        let cleaned = amountString.replacingOccurrences(of: ",", with: "")
        guard let value = Double(cleaned) else { return 0 }
        return Int(round(value * 100))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    HStack {
                        Text("RM")
                        TextField("0.00", text: $amountString)
                    }
                }
                Section("Remark") {
                    TextEditor(text: $remark)
                        .frame(minHeight: 60)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEdit ? "Edit Income" : "New Income")
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
        .frame(minWidth: 400, minHeight: 300)
    }

    private func populateIfEditing() {
        guard case .edit(let income) = mode else { return }
        date = income.date
        amountString = String(format: "%.2f", Double(income.amountCents) / 100.0)
        remark = income.remark
    }

    private func save() {
        switch mode {
        case .create:
            let income = Income(
                incomeNumber: RunningNumberGenerator.next(prefix: "IN", for: date, in: modelContext),
                date: date,
                amountCents: amountCents,
                remark: remark
            )
            modelContext.insert(income)
            try? modelContext.save()
        case .edit(let income):
            income.date = date
            income.amountCents = amountCents
            income.remark = remark
        }
        dismiss()
    }
}
