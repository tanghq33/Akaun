import AppKit
import Foundation
import PDFKit
import SwiftData
import Vision

// MARK: - Data Types

enum ImportState: Equatable {
    case pending
    case imported
    case failed(String)
}

enum DocumentType: String, Codable {
    case expense
    case income
}

struct ExtractedDocument: Identifiable {
    var id = UUID()
    var itemName: String
    var correspondent: String
    var dateString: String
    var date: Date
    var amountString: String
    var amountCents: Int
    var reference: String
    var category: String
    var documentType: DocumentType
    var sourceFile: URL
    var importState: ImportState = .pending
}

private struct OpenRouterResult: Decodable {
    var item: String
    var correspondent: String
    var date: String
    var amount: String
    var reference: String
    var category: String
    var document_type: String
}

// MARK: - Constants

private let openRouterURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

/// Average characters per PDF page below which the document is treated as scanned and OCR is applied.
private let scannedPdfCharThreshold: Double = 50

private func buildSystemPrompt(expenseCategories: [String], incomeCategories: [String], hint: String? = nil) -> String {
    let expCategoryList = expenseCategories.joined(separator: ", ")
    let incCategoryList = incomeCategories.joined(separator: ", ")
    var prompt = """
    You are a financial document data extraction assistant. Documents may be either expense receipts (money paid out) or income invoices/payment confirmations (money received).

    First, classify the document:
    - "expense" — the document records a purchase, payment made, or cost incurred
    - "income"  — the document records a sale, invoice issued, or payment received

    Return a JSON object with these fields:
    - document_type: string (must be exactly "expense" or "income")
    - item: string (description of the transaction — for expenses: what was purchased; for income: what service/product was invoiced; aim for under 40 characters; for 1–2 items use a concise name like "Kopi O, Kaya Toast"; for 3+ items use a brief summary like "Groceries" or "Web Design Services")
    - correspondent: string (the counterparty — vendor/merchant name for expenses, customer/payer name for income; use the full legal name as printed, e.g. "Grid System Marketing Sdn Bhd", "Sunrise Trading Enterprise")
    - date: string (a SINGLE date in YYYY-MM-DD format — never list multiple dates; for a payment receipt or invoice use the payment/invoice date; for a statement covering a date range use the period end date, e.g. for "2026-01-01 to 2026-01-31" return "2026-01-31"; for a transaction history use the most recent transaction date; return empty string if no single date can be determined)
    - amount: string (total amount paid/received including currency symbol, e.g. "RM 1200.00", "SGD 42.50"; use empty string if unknown)
    - reference: string (invoice number, receipt number, order ID, or any reference identifier; empty string if none)
    - category: string (choose from the correct list below based on document_type)

    Expense categories (use when document_type is "expense"):
    \(expCategoryList)

    Income categories (use when document_type is "income"):
    \(incCategoryList)

    Be precise. Use exact values from the document. If a field cannot be determined, use an empty string.
    """
    if let hint = hint, !hint.isEmpty {
        prompt += "\n\n## Categorization Hints\n\(hint)"
    }
    return prompt
}

private func buildJsonSchema() -> [String: Any] {
    [
        "name": "document_data",
        "strict": true,
        "schema": [
            "type": "object",
            "properties": [
                "document_type": ["type": "string"],
                "item":          ["type": "string"],
                "correspondent": ["type": "string"],
                "date":          ["type": "string"],
                "amount":        ["type": "string"],
                "reference":     ["type": "string"],
                "category":      ["type": "string"],
            ],
            "required": ["document_type", "item", "correspondent", "date", "amount", "reference", "category"],
            "additionalProperties": false,
        ] as [String: Any],
    ]
}

// MARK: - Text Extraction

func extractText(from url: URL) async throws -> String {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }

    let ext = url.pathExtension.lowercased()
    switch ext {
    case "pdf":
        return try await extractTextFromPDF(url: url)
    case "png", "jpg", "jpeg":
        return try await extractTextFromImage(url: url)
    default:
        throw NSError(domain: "DocumentProcessor", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported file type: \(ext)"])
    }
}

private func extractTextFromPDF(url: URL) async throws -> String {
    guard let doc = PDFDocument(url: url) else {
        throw NSError(domain: "DocumentProcessor", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Failed to open PDF: \(url.lastPathComponent)"])
    }

    var pageTexts: [String] = []
    for i in 0..<doc.pageCount {
        pageTexts.append(doc.page(at: i)?.string ?? "")
    }

    let totalChars = pageTexts.reduce(0) { $0 + $1.count }
    let avgChars = doc.pageCount > 0 ? Double(totalChars) / Double(doc.pageCount) : 0

    if avgChars < scannedPdfCharThreshold, doc.pageCount > 0 {
        // Scanned PDF — render and OCR each page
        var ocrTexts: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let text = try await ocrPDFPage(page)
            ocrTexts.append(text)
        }
        return ocrTexts.joined(separator: "\n")
    }

    return pageTexts.joined(separator: "\n")
}

private func ocrPDFPage(_ page: PDFPage) async throws -> String {
    let scale = 300.0 / 72.0
    let bounds = page.bounds(for: .mediaBox)
    let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let nsImage = page.thumbnail(of: pixelSize, for: .mediaBox)
            guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continuation.resume(throwing: NSError(domain: "DocumentProcessor", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to render PDF page to image"]))
                return
            }
            performOCR(on: cgImage, continuation: continuation)
        }
    }
}

private func extractTextFromImage(url: URL) async throws -> String {
    guard let nsImage = NSImage(contentsOf: url),
          let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw NSError(domain: "DocumentProcessor", code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Failed to load image: \(url.lastPathComponent)"])
    }
    return try await recognizeText(in: cgImage)
}

private func recognizeText(in cgImage: CGImage) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            performOCR(on: cgImage, continuation: continuation)
        }
    }
}

private func performOCR(on cgImage: CGImage, continuation: CheckedContinuation<String, Error>) {
    let request = VNRecognizeTextRequest { req, error in
        if let error = error {
            continuation.resume(throwing: error)
            return
        }
        let texts = (req.results as? [VNRecognizedTextObservation] ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
        continuation.resume(returning: texts.joined(separator: "\n"))
    }
    request.recognitionLevel = .accurate

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        continuation.resume(throwing: error)
    }
}

// MARK: - OpenRouter API

private func callOpenRouter(
    text: String,
    apiKey: String,
    model: String,
    maxTokens: Int,
    expenseCategories: [String],
    incomeCategories: [String],
    hint: String? = nil
) async throws -> OpenRouterResult {
    var payload: [String: Any] = [
        "model": model,
        "messages": [
            ["role": "system", "content": buildSystemPrompt(expenseCategories: expenseCategories, incomeCategories: incomeCategories, hint: hint)],
            ["role": "user", "content": "Extract the document data from the following text:\n\n\(text)"],
        ],
        "response_format": [
            "type": "json_schema",
            "json_schema": buildJsonSchema(),
        ] as [String: Any],
    ]
    if maxTokens > 0 {
        payload["max_tokens"] = maxTokens
    }

    #if DEBUG
    if let prettyData = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
       let prettyStr = String(data: prettyData, encoding: .utf8) {
        print("[DocumentProcessor] Request payload:\n\(prettyStr)")
    }
    #endif

    var urlRequest = URLRequest(url: openRouterURL)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)
    urlRequest.timeoutInterval = 60

    var lastError: Error = NSError(domain: "DocumentProcessor", code: 5,
        userInfo: [NSLocalizedDescriptionKey: "Failed after 3 attempts"])

    for attempt in 0..<3 {
        if attempt > 0 {
            let waitNs = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
            try await Task.sleep(nanoseconds: waitNs)
        }

        var responseData: Data?
        var statusCode: Int = 0

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                lastError = NSError(domain: "DocumentProcessor", code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response"])
                continue
            }
            responseData = data
            statusCode = http.statusCode
            #if DEBUG
            if let requestId = http.value(forHTTPHeaderField: "x-request-id") {
                print("[DocumentProcessor] x-request-id: \(requestId)")
            }
            #endif
        } catch {
            lastError = error
            continue
        }

        guard let data = responseData else { continue }

        if statusCode == 200 {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard let choices = body["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String,
                  let contentData = content.data(using: .utf8) else {
                throw NSError(domain: "DocumentProcessor", code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected API response structure"])
            }
            let result = try JSONDecoder().decode(OpenRouterResult.self, from: contentData)
            #if DEBUG
            print("[DocumentProcessor] Extracted — type: \"\(result.document_type)\" item: \"\(result.item)\" correspondent: \"\(result.correspondent)\" date: \"\(result.date)\" amount: \"\(result.amount)\" ref: \"\(result.reference)\" category: \"\(result.category)\"")
            #endif
            return result
        } else if [429, 500, 502, 503, 504].contains(statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            #if DEBUG
            print("[DocumentProcessor] HTTP \(statusCode) (attempt \(attempt + 1)): \(body)")
            #endif
            lastError = NSError(domain: "DocumentProcessor", code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode): \(String(body.prefix(300)))"])
        } else {
            let body = String(data: data, encoding: .utf8) ?? ""
            #if DEBUG
            print("[DocumentProcessor] HTTP \(statusCode): \(body)")
            #endif
            throw NSError(domain: "DocumentProcessor", code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "API error \(statusCode): \(String(body.prefix(500)))"])
        }
    }

    throw lastError
}

// MARK: - Helpers

func parseAmountCents(_ amountString: String) -> Int {
    var stripped = amountString
    while let first = stripped.first, !first.isNumber, first != "." {
        stripped.removeFirst()
    }
    stripped = stripped.replacingOccurrences(of: ",", with: "")
    let value = Double(stripped) ?? 0.0
    return Int((value * 100).rounded())
}

private let dateFormatters: [DateFormatter] = {
    let formats = [
        "yyyy-MM-dd",    // 2026-02-22  ← primary (ISO 8601, what AI is asked for)
        "yyyy/MM/dd",    // 2026/02/22
        "dd/MM/yyyy",    // 22/02/2026
        "MM/dd/yyyy",    // 02/22/2026
        "d MMM yyyy",    // 22 Feb 2026
        "d MMMM yyyy",   // 22 February 2026
        "MMM d, yyyy",   // Feb 22, 2026
        "MMMM d, yyyy",  // February 22, 2026
    ]
    return formats.map {
        let f = DateFormatter()
        f.dateFormat = $0
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }
}()

func parseReceiptDate(_ dateString: String) -> Date {
    let trimmed = dateString.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return .now }
    for f in dateFormatters {
        if let date = f.date(from: trimmed) { return date }
    }
    return .now
}

// MARK: - Top-Level Processing

func processDocuments(
    urls: [URL],
    apiKey: String,
    model: String,
    maxTokens: Int,
    expenseCategories: [String] = [],
    incomeCategories: [String] = [],
    progress: @escaping (Int, Int) -> Void
) async -> [ExtractedDocument] {
    let expCats = expenseCategories.isEmpty ? loadCategories() : expenseCategories
    let incCats = incomeCategories.isEmpty ? loadIncomeCategories() : incomeCategories
    var results: [ExtractedDocument] = []
    let total = urls.count

    for (index, url) in urls.enumerated() {
        progress(index + 1, total)

        do {
            let text = try await extractText(from: url)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                results.append(ExtractedDocument(
                    itemName: url.lastPathComponent, correspondent: "", dateString: "",
                    date: .now, amountString: "", amountCents: 0, reference: "",
                    category: "Other", documentType: .expense, sourceFile: url,
                    importState: .failed("No text extracted from file")
                ))
                continue
            }

            let apiResult = try await callOpenRouter(
                text: text, apiKey: apiKey, model: model, maxTokens: maxTokens,
                expenseCategories: expCats, incomeCategories: incCats
            )
            let parsedDate = parseReceiptDate(apiResult.date)
            let cents = parseAmountCents(apiResult.amount)
            let docType = DocumentType(rawValue: apiResult.document_type) ?? .expense

            results.append(ExtractedDocument(
                itemName: apiResult.item,
                correspondent: apiResult.correspondent,
                dateString: apiResult.date,
                date: parsedDate,
                amountString: apiResult.amount,
                amountCents: cents,
                reference: apiResult.reference,
                category: apiResult.category,
                documentType: docType,
                sourceFile: url,
                importState: .pending
            ))
        } catch {
            results.append(ExtractedDocument(
                itemName: url.lastPathComponent, correspondent: "", dateString: "",
                date: .now, amountString: "", amountCents: 0, reference: "",
                category: "Other", documentType: .expense, sourceFile: url,
                importState: .failed(error.localizedDescription)
            ))
        }
    }

    return results
}

// MARK: - Search Data Extraction

func extractAndStoreSearchText(for expense: Expense, in context: ModelContext) async {
    guard !expense.attachments.isEmpty else { return }
    var texts: [String] = []
    for attachment in expense.attachments {
        let url = DocumentStore.url(for: attachment.filename)
        if let text = try? await extractText(from: url),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            texts.append(text)
        }
    }
    let combined = texts.joined(separator: "\n\n")
    guard !combined.isEmpty else { return }
    if let existing = expense.searchData {
        existing.text = combined
    } else {
        let sd = ExpenseSearchData(text: combined)
        sd.expense = expense
        context.insert(sd)
    }
    try? context.save()
}

func extractAndStoreSearchText(for income: Income, in context: ModelContext) async {
    guard !income.attachments.isEmpty else { return }
    var texts: [String] = []
    for attachment in income.attachments {
        let url = DocumentStore.url(for: attachment.filename)
        if let text = try? await extractText(from: url),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            texts.append(text)
        }
    }
    let combined = texts.joined(separator: "\n\n")
    guard !combined.isEmpty else { return }
    if let existing = income.searchData {
        existing.text = combined
    } else {
        let sd = IncomeSearchData(text: combined)
        sd.income = income
        context.insert(sd)
    }
    try? context.save()
}

func extractAndStoreSearchText(for claim: Claim, in context: ModelContext) async {
    guard !claim.claimAttachments.isEmpty else { return }
    var texts: [String] = []
    for attachment in claim.claimAttachments {
        let url = DocumentStore.url(for: attachment.filename)
        if let text = try? await extractText(from: url),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            texts.append(text)
        }
    }
    let combined = texts.joined(separator: "\n\n")
    guard !combined.isEmpty else { return }
    if let existing = claim.searchData {
        existing.text = combined
    } else {
        let sd = ClaimSearchData(text: combined)
        sd.claim = claim
        context.insert(sd)
    }
    try? context.save()
}

// MARK: - Single-File Processing (for queue-based import)

func processSingleFile(
    url: URL,
    apiKey: String,
    model: String,
    maxTokens: Int,
    expenseCategories: [String] = [],
    incomeCategories: [String] = [],
    hint: String? = nil,
    onStateChange: @escaping (QueueItemState) -> Void
) async -> Result<ExtractedDocument, Error> {
    let expCats = expenseCategories.isEmpty ? loadCategories() : expenseCategories
    let incCats = incomeCategories.isEmpty ? loadIncomeCategories() : incomeCategories
    onStateChange(.extracting)
    do {
        let text = try await extractText(from: url)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(NSError(domain: "DocumentProcessor", code: 8,
                userInfo: [NSLocalizedDescriptionKey: "No text could be extracted from this file"]))
        }
        onStateChange(.calling)
        let apiResult = try await callOpenRouter(
            text: text, apiKey: apiKey, model: model, maxTokens: maxTokens,
            expenseCategories: expCats, incomeCategories: incCats, hint: hint
        )
        let docType = DocumentType(rawValue: apiResult.document_type) ?? .expense
        let document = ExtractedDocument(
            itemName: apiResult.item,
            correspondent: apiResult.correspondent,
            dateString: apiResult.date,
            date: parseReceiptDate(apiResult.date),
            amountString: apiResult.amount,
            amountCents: parseAmountCents(apiResult.amount),
            reference: apiResult.reference,
            category: apiResult.category,
            documentType: docType,
            sourceFile: url,
            importState: .pending
        )
        return .success(document)
    } catch {
        return .failure(error)
    }
}
