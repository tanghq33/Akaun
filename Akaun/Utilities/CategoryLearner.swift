import Foundation
import SwiftData

// MARK: - Public types

struct CategoryDataPoint {
    let label:    String
    let category: String
}

enum DiffAction: String, Codable {
    case add
    case remove
}

struct CategoryDiff: Identifiable {
    var id        = UUID()
    var name:      String
    var action:    DiffAction
    var reasoning: String
    var isSelected: Bool = true
}

struct CategorySuggestions {
    var expenseDiffs: [CategoryDiff]
    var incomeDiffs:  [CategoryDiff]
}

enum ReassignableRef {
    case expense(Expense)
    case income(Income)
}

struct ReassignmentSuggestion: Identifiable {
    var id               = UUID()
    let ref:              ReassignableRef
    let recordLabel:      String
    let currentCategory:  String
    var suggestedCategory: String
}

// MARK: - Private Codable helpers

private struct RawDiff: Codable {
    let name:      String
    let action:    String
    let reasoning: String
}

private struct RawSuggestions: Codable {
    let expense_diffs: [RawDiff]
    let income_diffs:  [RawDiff]
}

private struct RawReassignment: Codable {
    let index:        Int
    let new_category: String
}

private struct RawReassignments: Codable {
    let reassignments: [RawReassignment]
}

// MARK: - JSON schemas

private func buildSuggestionsSchema() -> [String: Any] {
    let diffItem: [String: Any] = [
        "type": "object",
        "properties": [
            "name":      ["type": "string"],
            "action":    ["type": "string", "enum": ["add", "remove"]],
            "reasoning": ["type": "string"],
        ] as [String: Any],
        "required": ["name", "action", "reasoning"],
        "additionalProperties": false,
    ]
    return [
        "name":   "category_suggestions",
        "strict": true,
        "schema": [
            "type": "object",
            "properties": [
                "expense_diffs": ["type": "array", "items": diffItem] as [String: Any],
                "income_diffs":  ["type": "array", "items": diffItem] as [String: Any],
            ] as [String: Any],
            "required": ["expense_diffs", "income_diffs"],
            "additionalProperties": false,
        ] as [String: Any],
    ]
}

private func buildReassignmentsSchema() -> [String: Any] {
    [
        "name":   "reassignments",
        "strict": true,
        "schema": [
            "type": "object",
            "properties": [
                "reassignments": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "index":        ["type": "integer"],
                            "new_category": ["type": "string"],
                        ] as [String: Any],
                        "required": ["index", "new_category"],
                        "additionalProperties": false,
                    ] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
            "required": ["reassignments"],
            "additionalProperties": false,
        ] as [String: Any],
    ]
}

// MARK: - System prompts

private func buildHintSystemPrompt() -> String {
    """
    You are a bookkeeping assistant. Based on a sample of an individual's expense records, \
    write a concise 2–4 sentence paragraph describing their typical spending patterns.
    This paragraph will be injected into an AI receipt-parsing system prompt to improve \
    category accuracy for this specific user.
    Focus on: dominant categories, distinctive vendor or supplier patterns, and anything that helps \
    distinguish between similar categories for this user. Be specific to the data — no generic advice.
    Use third person ("This user frequently…" or "Common expenses include…"). \
    Keep the response under 100 words. Return only the paragraph — no headings, no lists.
    """
}

private func buildSuggestionsSystemPrompt() -> String {
    """
    You are a bookkeeping category advisor for a small business owner.

    INPUT FORMAT
    Each record line: item name | current category | N records

    YOUR TASK
    Analyse the full record set and suggest improvements to the category structure.

    add — propose a new category when multiple items share a clear theme:
      - Examine every item labelled "Other" and identify every distinct semantic group, even small ones.
      - Examine all other categories too; if items clearly belong somewhere more specific, suggest it.
      - Return one suggestion per distinct group. Never merge different item types into one suggestion.

    remove — propose removing an existing category only when:
      - It has zero records in the dataset, AND
      - An existing category already covers the same purpose.

    RULES
    1. Never suggest removing "Other" — it is always required as a fallback.
    2. Never suggest adding a category that already exists.
    3. Category names must be broad and reusable — name the general type, not the specific product
       (e.g. "Materials" not "3D Printing Filament", "Maintenance" not "Printer Servicing").
    4. Prefer a single-word name; use two words only when one word would be genuinely ambiguous.
    5. Give one concise sentence of reasoning per suggestion.
    6. Return empty arrays if no improvements are warranted.
    """
}

private func buildReassignmentsSystemPrompt() -> String {
    """
    You are a bookkeeping data migration assistant.

    Records are listed with an index, their type (expense/income), their label, and current category.
    Their current category is being removed. Suggest the best replacement from the valid category list provided.
    Use "Other" if no category fits well.
    Return one entry per record in the input list.
    """
}

// MARK: - HTTP helper

private let openRouterChatURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

private func callOpenRouterForCategory(payload: [String: Any], apiKey: String) async throws -> Data {
    var urlRequest = URLRequest(url: openRouterChatURL)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)
    urlRequest.timeoutInterval = 60

    var lastError: Error = NSError(domain: "CategoryLearner", code: 5,
        userInfo: [NSLocalizedDescriptionKey: "Failed after 3 attempts"])

    for attempt in 0..<3 {
        if attempt > 0 {
            let waitNs = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
            try await Task.sleep(nanoseconds: waitNs)
        }

        var responseData: Data?
        var statusCode = 0

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                lastError = NSError(domain: "CategoryLearner", code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response"])
                continue
            }
            responseData = data
            statusCode = http.statusCode
        } catch {
            lastError = error
            continue
        }

        guard let data = responseData else { continue }

        if statusCode == 200 {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard let choices   = body["choices"] as? [[String: Any]],
                  let first     = choices.first,
                  let message   = first["message"] as? [String: Any],
                  let content   = message["content"] as? String,
                  let contentData = content.data(using: .utf8) else {
                throw NSError(domain: "CategoryLearner", code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected API response structure"])
            }
            return contentData
        } else if [429, 500, 502, 503, 504].contains(statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[CategoryLearner] HTTP \(statusCode) (attempt \(attempt + 1)): \(body)")
            lastError = NSError(domain: "CategoryLearner", code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode)"])
        } else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "CategoryLearner", code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "API error \(statusCode): \(String(body.prefix(500)))"])
        }
    }

    throw lastError
}

// MARK: - Public API

func suggestCategoryImprovements(
    expenseItems: [CategoryDataPoint],
    incomeItems:  [CategoryDataPoint],
    expenseCats:  [String],
    incomeCats:   [String],
    apiKey:       String,
    model:        String,
    maxTokens:    Int
) async throws -> CategorySuggestions {
    func buildGroupedLines(_ items: [CategoryDataPoint], limit: Int) -> String {
        var counts: [String: Int] = [:]
        for dp in items {
            counts["\(dp.label)|\(dp.category)", default: 0] += 1
        }
        var byCategory: [String: [(label: String, count: Int)]] = [:]
        for (key, count) in counts {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            byCategory[parts[1], default: []].append((label: parts[0], count: count))
        }
        let sortedCats = byCategory.keys.sorted { a, b in
            if a == "Other" { return true }
            if b == "Other" { return false }
            return a < b
        }
        var lines: [String] = []
        for cat in sortedCats {
            guard lines.count < limit else { break }
            let entries = (byCategory[cat] ?? []).sorted { $0.count > $1.count }
            for e in entries {
                guard lines.count < limit else { break }
                lines.append("- \(e.label) | \(cat) | \(e.count) record\(e.count == 1 ? "" : "s")")
            }
        }
        return lines.joined(separator: "\n")
    }

    let expLines = buildGroupedLines(expenseItems, limit: 200)
    let incLines = buildGroupedLines(incomeItems,  limit: 100)

    let userMessage = """
    Current expense categories: \(expenseCats.joined(separator: ", "))

    Current income categories: \(incomeCats.joined(separator: ", "))

    Expense records (up to 200, grouped by category — Other first):
    \(expLines.isEmpty ? "(no expense records)" : expLines)

    Income records (up to 100, grouped by category — Other first):
    \(incLines.isEmpty ? "(no income records)" : incLines)
    """

    var payload: [String: Any] = [
        "model":    model,
        "messages": [
            ["role": "system", "content": buildSuggestionsSystemPrompt()],
            ["role": "user",   "content": userMessage],
        ],
        "response_format": [
            "type":        "json_schema",
            "json_schema": buildSuggestionsSchema(),
        ] as [String: Any],
    ]
    if maxTokens > 0 { payload["max_tokens"] = maxTokens }

    let data = try await callOpenRouterForCategory(payload: payload, apiKey: apiKey)
    let raw  = try JSONDecoder().decode(RawSuggestions.self, from: data)

    let expSet = Set(expenseCats)
    let incSet = Set(incomeCats)

    func toDiffs(_ rawList: [RawDiff], currentSet: Set<String>) -> [CategoryDiff] {
        rawList.compactMap { r -> CategoryDiff? in
            guard let action = DiffAction(rawValue: r.action) else { return nil }
            if action == .remove && r.name == "Other"            { return nil } // always keep Other
            if action == .add    && currentSet.contains(r.name)  { return nil } // already exists
            if action == .remove && !currentSet.contains(r.name) { return nil } // doesn't exist
            return CategoryDiff(name: r.name, action: action, reasoning: r.reasoning)
        }
    }

    return CategorySuggestions(
        expenseDiffs: toDiffs(raw.expense_diffs, currentSet: expSet),
        incomeDiffs:  toDiffs(raw.income_diffs,  currentSet: incSet)
    )
}

func generateCategorizationHint(
    expenses:   [CategoryDataPoint],
    categories: [String],
    apiKey:     String,
    model:      String,
    maxTokens:  Int
) async throws -> String {
    let sample: [CategoryDataPoint] = {
        var seen = Set<String>()
        return expenses
            .filter { !$0.label.isEmpty }
            .filter { seen.insert("\($0.label)|\($0.category)").inserted }
            .prefix(100)
            .map { $0 }
    }()

    guard !sample.isEmpty else {
        throw NSError(domain: "CategoryLearner", code: 10,
            userInfo: [NSLocalizedDescriptionKey: "No expense data to generate a hint from"])
    }

    let lines = sample.map { "- \($0.label) | \($0.category)" }.joined(separator: "\n")
    let userMessage = """
    Available categories: \(categories.joined(separator: ", "))

    Sample of past expenses (item | category):
    \(lines)
    """

    var payload: [String: Any] = [
        "model":    model,
        "messages": [
            ["role": "system", "content": buildHintSystemPrompt()],
            ["role": "user",   "content": userMessage],
        ],
        "max_tokens": 256,
    ]
    if maxTokens > 0 { payload["max_tokens"] = min(maxTokens, 256) }

    let data = try await callOpenRouterForCategory(payload: payload, apiKey: apiKey)
    let hint = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !hint.isEmpty else {
        throw NSError(domain: "CategoryLearner", code: 11,
            userInfo: [NSLocalizedDescriptionKey: "LLM returned an empty hint"])
    }
    return hint
}

func suggestReassignments(
    expenses:       [(record: Expense, label: String)],
    incomes:        [(record: Income,  label: String)],
    newExpenseCats: [String],
    newIncomeCats:  [String],
    apiKey:         String,
    model:          String,
    maxTokens:      Int
) async throws -> [ReassignmentSuggestion] {
    struct Item {
        let index:           Int
        let ref:             ReassignableRef
        let label:           String
        let currentCategory: String
        let typeName:        String
    }

    var items: [Item] = []
    for (r, label) in expenses {
        items.append(Item(index: items.count, ref: .expense(r),
                          label: label, currentCategory: r.category, typeName: "expense"))
    }
    for (r, label) in incomes {
        items.append(Item(index: items.count, ref: .income(r),
                          label: label, currentCategory: r.category, typeName: "income"))
    }

    guard !items.isEmpty else { return [] }

    let itemLines = items.map {
        "- index \($0.index) | \($0.typeName) | \($0.label) | currently: \($0.currentCategory)"
    }.joined(separator: "\n")

    let userMessage = """
    Valid expense categories: \(newExpenseCats.joined(separator: ", "))
    Valid income categories:  \(newIncomeCats.joined(separator: ", "))

    Records needing reassignment:
    \(itemLines)
    """

    var payload: [String: Any] = [
        "model":    model,
        "messages": [
            ["role": "system", "content": buildReassignmentsSystemPrompt()],
            ["role": "user",   "content": userMessage],
        ],
        "response_format": [
            "type":        "json_schema",
            "json_schema": buildReassignmentsSchema(),
        ] as [String: Any],
    ]
    if maxTokens > 0 { payload["max_tokens"] = maxTokens }

    let data = try await callOpenRouterForCategory(payload: payload, apiKey: apiKey)
    let raw  = try JSONDecoder().decode(RawReassignments.self, from: data)

    var suggMap: [Int: String] = [:]
    for r in raw.reassignments where r.index >= 0 && r.index < items.count {
        suggMap[r.index] = r.new_category
    }

    return items.map { item in
        ReassignmentSuggestion(
            ref:               item.ref,
            recordLabel:       item.label,
            currentCategory:   item.currentCategory,
            suggestedCategory: suggMap[item.index] ?? "Other"
        )
    }
}
