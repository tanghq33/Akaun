import SwiftUI
import SwiftData

enum DashboardPeriod: CaseIterable {
    case monthMinus2, monthMinus1, currentMonth, currentYear

    private static let labelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    var label: String {
        let cal = Calendar.current
        switch self {
        case .currentMonth:
            return Self.labelFormatter.string(from: Date.now)
        case .monthMinus1:
            let date = cal.date(byAdding: .month, value: -1, to: Date.now) ?? Date.now
            return Self.labelFormatter.string(from: date)
        case .monthMinus2:
            let date = cal.date(byAdding: .month, value: -2, to: Date.now) ?? Date.now
            return Self.labelFormatter.string(from: date)
        case .currentYear:
            return String(cal.component(.year, from: Date.now))
        }
    }
}

struct DashboardView: View {
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]

    @State private var period: DashboardPeriod = .currentMonth

    init() {
        let fiveYearsAgo = Calendar.current.date(byAdding: .year, value: -5, to: Date.now) ?? Date.distantPast
        _expenses = Query(filter: #Predicate<Expense> { $0.date >= fiveYearsAgo })
        _incomes = Query(filter: #Predicate<Income> { $0.date >= fiveYearsAgo })
    }

    private var cashFlowData: [MonthlyNetData] {
        computeCashFlowData(expenses: expenses, incomes: incomes, period: period)
    }
    private var trendData: [MonthlySeriesData] {
        computeTrendData(expenses: expenses, incomes: incomes, period: period)
    }
    private var categoryData: [CategoryData] {
        computeCategoryData(expenses: expenses, period: period)
    }
    private var periodTotals: (incomeCents: Int, expenseCents: Int) {
        computePeriodTotals(expenses: expenses, incomes: incomes, period: period)
    }

    var body: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                MonthlyTrendChartView(data: trendData, period: period)
                ProfitThisMonthView(incomeCents: periodTotals.incomeCents, expenseCents: periodTotals.expenseCents, period: period)
            }
            GridRow {
                ExpenseCategoryChartView(data: categoryData, period: period)
                CashFlowChartView(data: cashFlowData)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Period", selection: $period) {
                    ForEach(DashboardPeriod.allCases, id: \.self) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }
}
