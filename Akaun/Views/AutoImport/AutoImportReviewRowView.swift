import SwiftUI
import SwiftData

struct AutoImportReviewRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AutoImportQueue.self) private var queue

    @Bindable var item: AutoImportQueueItem

    @AppStorage("autoImport.apiKey") private var apiKey = ""
    @AppStorage("autoImport.model") private var model = "google/gemini-2.5-flash"
    @AppStorage("autoImport.maxTokens") private var maxTokens = 1024

    @State private var amountString = ""
    @State private var quickLookCoordinator = QuickLookCoordinator()
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Header ──────────────────────────────────────
            HStack(spacing: 8) {
                statusIcon
                VStack(alignment: .leading, spacing: 1) {
                    let filename = item.sourceFile.lastPathComponent
                    let displayName = item.itemName.isEmpty ? filename : item.itemName
                    Button(displayName) {
                        quickLookCoordinator.show(urls: [item.sourceFile], at: 0)
                    }
                    .buttonStyle(.plain)
                    .font(.body)
                    .lineLimit(1)
                    if !item.itemName.isEmpty {
                        Button(filename) {
                            quickLookCoordinator.show(urls: [item.sourceFile], at: 0)
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
                Spacer()
                Button {
                    quickLookCoordinator.show(urls: [item.sourceFile], at: 0)
                } label: {
                    Image(systemName: "doc.viewfinder")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(isHovering ? 1 : 0)
                actionButton
            }
            .onHover { isHovering = $0 }

            // ── Error banner (only for .failed) ─────────────
            if case .failed(let msg) = item.state {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            // ── Form fields (hidden when .imported) ─────────
            if item.state != .imported {
                Divider()
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Type")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                            .gridColumnAlignment(.trailing)
                        Picker("", selection: $item.documentType) {
                            Text("Expense").tag(DocumentType.expense)
                            Text("Income").tag(DocumentType.income)
                        }
                        .labelsHidden()
                    }
                    GridRow {
                        Text(item.documentType == .income ? "Description" : "Item")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                            .gridColumnAlignment(.trailing)
                        TextField(item.documentType == .income ? "Description" : "Item name",
                                  text: $item.itemName)
                            .textFieldStyle(.roundedBorder).font(.callout)
                    }
                    GridRow {
                        Text(item.documentType == .income ? "Source" : "Supplier")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                            .gridColumnAlignment(.trailing)
                        TextField(item.documentType == .income ? "Payer / customer" : "Supplier",
                                  text: $item.supplier)
                            .textFieldStyle(.roundedBorder).font(.callout)
                    }
                    GridRow {
                        Text("Date").font(.caption).foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                            .gridColumnAlignment(.trailing)
                        WideDatePicker(selection: item.date) { item.date = $0 }
                    }
                    GridRow {
                        Text("Amount").font(.caption).foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                            .gridColumnAlignment(.trailing)
                        TextField("0.00", text: $amountString)
                            .textFieldStyle(.roundedBorder).font(.callout)
                            .frame(maxWidth: 120)
                            .onChange(of: amountString) { _, new in
                                amountString = sanitiseAmount(new)
                                item.amountCents = parseCents(amountString)
                            }
                    }
                    GridRow {
                        Text("Ref").font(.caption).foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                            .gridColumnAlignment(.trailing)
                        TextField("Reference", text: $item.reference)
                            .textFieldStyle(.roundedBorder).font(.callout)
                    }
                    GridRow {
                        Text("Category").font(.caption).foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                            .gridColumnAlignment(.trailing)
                        let categories = item.documentType == .income
                            ? loadIncomeCategories()
                            : loadCategories()
                        Picker("", selection: $item.category) {
                            ForEach(categories, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .onChange(of: item.documentType) { _, _ in
            item.category = "Other"
        }
        .onAppear {
            amountString = item.amountCents > 0
                ? String(format: "%.2f", Double(item.amountCents) / 100.0)
                : ""
        }
    }

    // MARK: - Status Icon

    private var statusIcon: some View {
        Group {
            switch item.state {
            case .extracting:
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
            case .calling:
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .foregroundStyle(Color.accentColor)
            case .ready:
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.orange)
            case .imported:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.subheadline)
        .frame(width: 18)
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        switch item.state {
        case .ready:
            Button("Import") {
                queue.importItem(item, in: modelContext)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .imported:
            Button("Imported") {}
                .disabled(true)
                .controlSize(.small)
        case .failed:
            Button("Retry") {
                queue.retryItem(item, apiKey: apiKey, model: model, maxTokens: maxTokens,
                                expenseCategories: loadCategories(), incomeCategories: loadIncomeCategories())
            }
            .controlSize(.small)
        case .extracting, .calling:
            ProgressView()
                .controlSize(.small)
        }
    }

    // MARK: - Helpers

    private func sanitiseAmount(_ input: String) -> String {
        var result = ""
        var hasDot = false
        var decimalCount = 0
        for ch in input {
            if ch.isNumber {
                if hasDot {
                    if decimalCount < 2 { result.append(ch); decimalCount += 1 }
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
        Int(((Double(string) ?? 0.0) * 100).rounded())
    }
}
