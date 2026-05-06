import SwiftUI

struct ExpenseFilterView: View {
    @Binding var filter: ExpenseFilter

    @State private var categories: [String] = []
    @State private var minAmountText: String = ""
    @State private var maxAmountText: String = ""
    // H6: pending dates remembered across filter clears so the picker doesn't reset to today
    @State private var pendingDateFrom: Date = Date()
    @State private var pendingDateTo: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    filterSection("Status") {
                        ForEach(ExpenseStatus.allCases, id: \.self) { status in
                            Toggle(status.rawValue, isOn: Binding(
                                get: { filter.statuses.contains(status) },
                                set: { included in
                                    if included { filter.statuses.insert(status) }
                                    else { filter.statuses.remove(status) }
                                }
                            ))
                        }
                    }

                    Divider()

                    filterSection("Category") {
                        ForEach(categories, id: \.self) { category in
                            Toggle(category, isOn: Binding(
                                get: { filter.categories.contains(category) },
                                set: { included in
                                    if included { filter.categories.insert(category) }
                                    else { filter.categories.remove(category) }
                                }
                            ))
                        }
                    }

                    Divider()

                    filterSection("Date Range") {
                        // H6: checkbox toggles the filter on/off; picker only commits when active
                        HStack {
                            Toggle(isOn: Binding(
                                get: { filter.dateFrom != nil },
                                set: { active in filter.dateFrom = active ? pendingDateFrom : nil }
                            )) {
                                Text("From").frame(width: 36, alignment: .leading)
                            }
                            .toggleStyle(.checkbox)
                            WideDatePicker(selection: filter.dateFrom ?? pendingDateFrom) { newDate in
                                pendingDateFrom = newDate
                                if filter.dateFrom != nil { filter.dateFrom = newDate }
                            }
                            .disabled(filter.dateFrom == nil)
                        }

                        HStack {
                            Toggle(isOn: Binding(
                                get: { filter.dateTo != nil },
                                set: { active in filter.dateTo = active ? pendingDateTo : nil }
                            )) {
                                Text("To").frame(width: 36, alignment: .leading)
                            }
                            .toggleStyle(.checkbox)
                            WideDatePicker(selection: filter.dateTo ?? pendingDateTo) { newDate in
                                pendingDateTo = newDate
                                if filter.dateTo != nil { filter.dateTo = newDate }
                            }
                            .disabled(filter.dateTo == nil)
                        }
                    }

                    Divider()

                    filterSection("Amount (RM)") {
                        HStack {
                            Text("Min")
                                .frame(width: 36, alignment: .leading)
                            TextField("0.00", text: $minAmountText)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: minAmountText) { _, val in
                                    filter.amountMinCents = parseCents(val)
                                }
                        }
                        HStack {
                            Text("Max")
                                .frame(width: 36, alignment: .leading)
                            TextField("0.00", text: $maxAmountText)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: maxAmountText) { _, val in
                                    filter.amountMaxCents = parseCents(val)
                                }
                        }
                    }
                }
            }
            .scrollIndicators(.never)

            if filter.isActive {
                Divider()
                // L3: .destructive role already tints the button red — no .foregroundStyle(.red) needed
                Button("Clear All Filters", role: .destructive) {
                    filter.clear()
                    minAmountText = ""
                    maxAmountText = ""
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 280)
        .onAppear {
            categories = loadCategories()
            if let min = filter.amountMinCents {
                minAmountText = String(format: "%.2f", Double(min) / 100)
            }
            if let max = filter.amountMaxCents {
                maxAmountText = String(format: "%.2f", Double(max) / 100)
            }
            // H6: sync pending dates with any existing filter values
            if let from = filter.dateFrom { pendingDateFrom = from }
            if let to = filter.dateTo { pendingDateTo = to }
        }
        // M6: refresh categories if user edits them in Settings while the popover is open
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            categories = loadCategories()
        }
    }

    @ViewBuilder
    private func filterSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 2)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // H7: reject scientific notation (Double("1e3") would silently parse as 1000)
    private func parseCents(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        guard cleaned.allSatisfy({ $0.isNumber || $0 == "." }),
              cleaned.filter({ $0 == "." }).count <= 1 else { return nil }
        guard let amount = Double(cleaned), amount >= 0 else { return nil }
        return Int((amount * 100).rounded())
    }
}
