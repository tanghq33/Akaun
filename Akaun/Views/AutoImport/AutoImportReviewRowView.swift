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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Header ──────────────────────────────────────
            HStack(spacing: 8) {
                statusIcon
                VStack(alignment: .leading, spacing: 1) {
                    let filename = item.sourceFile.lastPathComponent
                    let displayName = item.itemName.isEmpty ? filename : item.itemName
                    Text(displayName)
                        .font(.body)
                        .lineLimit(1)
                    if !item.itemName.isEmpty {
                        Text(filename)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                actionButton
            }

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
                        Text("Item").font(.caption).foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        TextField("Item name", text: $item.itemName)
                            .textFieldStyle(.roundedBorder).font(.callout)
                    }
                    GridRow {
                        Text("Supplier").font(.caption).foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        TextField("Supplier", text: $item.supplier)
                            .textFieldStyle(.roundedBorder).font(.callout)
                    }
                    GridRow {
                        Text("Date").font(.caption).foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        WideDatePicker(selection: $item.date)
                    }
                    GridRow {
                        Text("Amount").font(.caption).foregroundStyle(.secondary)
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
                        Text("Status").font(.caption).foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        Picker("", selection: $item.status) {
                            Text("Unpaid").tag(ExpenseStatus.unpaid)
                            Text("Paid").tag(ExpenseStatus.paid)
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }
                    GridRow {
                        Text("Ref").font(.caption).foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        TextField("Reference", text: $item.reference)
                            .textFieldStyle(.roundedBorder).font(.callout)
                    }
                    GridRow {
                        Text("Category").font(.caption).foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        Picker("", selection: $item.category) {
                            ForEach(loadCategories(), id: \.self) { Text($0).tag($0) }
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
                queue.retryItem(item, apiKey: apiKey, model: model, maxTokens: maxTokens, categories: loadCategories())
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
