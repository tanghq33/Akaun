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
