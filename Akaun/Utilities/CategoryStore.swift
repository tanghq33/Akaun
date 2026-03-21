import Foundation

let defaultCategories = [
    "Food & Beverage", "Transport", "Accommodation",
    "Office Supplies", "Utilities", "Entertainment",
    "Medical", "Other",
]

func loadCategories() -> [String] {
    UserDefaults.standard.stringArray(forKey: "expense.categories") ?? defaultCategories
}

func saveCategories(_ categories: [String]) {
    UserDefaults.standard.set(categories, forKey: "expense.categories")
}

let defaultIncomeCategories = [
    "Sales Revenue", "Service Income", "Rental Income",
    "Investment / Interest", "Refund", "Other",
]

func loadIncomeCategories() -> [String] {
    UserDefaults.standard.stringArray(forKey: "income.categories") ?? defaultIncomeCategories
}

func saveIncomeCategories(_ categories: [String]) {
    UserDefaults.standard.set(categories, forKey: "income.categories")
}
