import AppKit
import Foundation
import PDFKit
import Vision

// MARK: - Data Types

enum ImportState: Equatable {
    case pending
    case imported
    case failed(String)
}

struct ExtractedReceipt: Identifiable {
    var id = UUID()
    var itemName: String
    var supplier: String
    var dateString: String
    var date: Date
    var amountString: String
    var amountCents: Int
    var reference: String
    var category: String
    var sourceFile: URL
    var importState: ImportState = .pending
}

private struct OpenRouterResult: Decodable {
    var item: String
    var supplier: String
    var date: String
    var amount: String
    var reference: String
    var category: String
}

// MARK: - Constants

private let openRouterURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

private func buildSystemPrompt(categories: [String], hint: String? = nil) -> String {
    let categoryList = categories.joined(separator: ", ")
    var prompt = """
    You are a receipt data extraction assistant. Extract structured bookkeeping data from the provided receipt text.

    Return a JSON object with these fields:
    - item: string (what was purchased, always keep it short and human-readable — aim for under 40 characters total; for 1–2 items use a concise name like "Kopi O, Kaya Toast" or "Nike Air Max"; for 3+ items or when individual names would be too long, use a brief summary like "Groceries", "Team lunch", "Flight SIN→KUL"; include brand only when it's meaningful, e.g. "Apple AirPods", skip brand for generic items like "Office supplies")
    - supplier: string (vendor / store / merchant name; look for it at the top of the receipt or invoice — it is usually the first prominent name, often followed by a legal suffix like Sdn Bhd, Bhd, Corporation, Corp, Inc, Ltd, LLC, Enterprise, Enterprises, Trading, or a registration number; use the full legal name as printed, e.g. "Grid System Marketing Sdn Bhd", "Sunrise Trading Enterprise")
    - date: string (YYYY-MM-DD format of the payment date or order date; if multiple dates appear on the receipt, prefer the payment/transaction date; empty string if unknown)
    - amount: string (total amount paid including currency symbol, e.g. "SGD 42.50", "USD 9.99"; use empty string if unknown)
    - reference: string (invoice number, receipt number, order ID, or any reference identifier on the receipt; empty string if none)
    - category: string (expense category — must be exactly one of: \(categoryList); choose the closest match, default to "Other")

    Be precise. Use exact values from the receipt. If a field cannot be determined, use an empty string.
    """
    if let hint = hint, !hint.isEmpty {
        prompt += "\n\n## Categorization Hints\n\(hint)"
    }
    return prompt
}

private func buildJsonSchema() -> [String: Any] {
    [
        "name": "receipt_data",
        "strict": true,
        "schema": [
            "type": "object",
            "properties": [
                "item":      ["type": "string"],
                "supplier":  ["type": "string"],
                "date":      ["type": "string"],
                "amount":    ["type": "string"],
                "reference": ["type": "string"],
                "category":  ["type": "string"],
            ],
            "required": ["item", "supplier", "date", "amount", "reference", "category"],
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
        throw NSError(domain: "ReceiptProcessor", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported file type: \(ext)"])
    }
}

private func extractTextFromPDF(url: URL) async throws -> String {
    guard let doc = PDFDocument(url: url) else {
        throw NSError(domain: "ReceiptProcessor", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Failed to open PDF: \(url.lastPathComponent)"])
    }

    var pageTexts: [String] = []
    for i in 0..<doc.pageCount {
        pageTexts.append(doc.page(at: i)?.string ?? "")
    }

    let totalChars = pageTexts.reduce(0) { $0 + $1.count }
    let avgChars = doc.pageCount > 0 ? Double(totalChars) / Double(doc.pageCount) : 0

    if avgChars < 50, doc.pageCount > 0 {
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
                continuation.resume(throwing: NSError(domain: "ReceiptProcessor", code: 3,
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
        throw NSError(domain: "ReceiptProcessor", code: 4,
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

private func callOpenRouter(text: String, apiKey: String, model: String, maxTokens: Int, categories: [String], hint: String? = nil) async throws -> OpenRouterResult {
    var payload: [String: Any] = [
        "model": model,
        "messages": [
            ["role": "system", "content": buildSystemPrompt(categories: categories, hint: hint)],
            ["role": "user", "content": "Extract the receipt data from the following text:\n\n\(text)"],
        ],
        "response_format": [
            "type": "json_schema",
            "json_schema": buildJsonSchema(),
        ] as [String: Any],
    ]
    if maxTokens > 0 {
        payload["max_tokens"] = maxTokens
    }

    if let prettyData = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
       let prettyStr = String(data: prettyData, encoding: .utf8) {
        print("[ReceiptProcessor] Request payload:\n\(prettyStr)")
    }

    var urlRequest = URLRequest(url: openRouterURL)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)
    urlRequest.timeoutInterval = 60

    var lastError: Error = NSError(domain: "ReceiptProcessor", code: 5,
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
                lastError = NSError(domain: "ReceiptProcessor", code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response"])
                continue
            }
            responseData = data
            statusCode = http.statusCode
            if let requestId = http.value(forHTTPHeaderField: "x-request-id") {
                print("[ReceiptProcessor] x-request-id: \(requestId)")
            }
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
                throw NSError(domain: "ReceiptProcessor", code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected API response structure"])
            }
            let result = try JSONDecoder().decode(OpenRouterResult.self, from: contentData)
            print("[ReceiptProcessor] Extracted — item: \"\(result.item)\" supplier: \"\(result.supplier)\" date: \"\(result.date)\" amount: \"\(result.amount)\" ref: \"\(result.reference)\" category: \"\(result.category)\"")
            return result
        } else if [429, 500, 502, 503, 504].contains(statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[ReceiptProcessor] HTTP \(statusCode) (attempt \(attempt + 1)): \(body)")
            lastError = NSError(domain: "ReceiptProcessor", code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode): \(String(body.prefix(300)))"])
        } else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[ReceiptProcessor] HTTP \(statusCode): \(body)")
            throw NSError(domain: "ReceiptProcessor", code: statusCode,
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

private let isoDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

func parseReceiptDate(_ dateString: String) -> Date {
    isoDateFormatter.date(from: dateString) ?? .now
}

// MARK: - Top-Level Processing

func processReceipts(
    urls: [URL],
    apiKey: String,
    model: String,
    maxTokens: Int,
    categories: [String] = [],
    progress: @escaping (Int, Int) -> Void
) async -> [ExtractedReceipt] {
    let cats = categories.isEmpty ? loadCategories() : categories
    var results: [ExtractedReceipt] = []
    let total = urls.count

    for (index, url) in urls.enumerated() {
        progress(index + 1, total)

        do {
            let text = try await extractText(from: url)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                results.append(ExtractedReceipt(
                    itemName: url.lastPathComponent, supplier: "", dateString: "",
                    date: .now, amountString: "", amountCents: 0, reference: "",
                    category: "Other", sourceFile: url,
                    importState: .failed("No text extracted from file")
                ))
                continue
            }

            let apiResult = try await callOpenRouter(text: text, apiKey: apiKey, model: model, maxTokens: maxTokens, categories: cats)
            let parsedDate = parseReceiptDate(apiResult.date)
            let cents = parseAmountCents(apiResult.amount)

            results.append(ExtractedReceipt(
                itemName: apiResult.item,
                supplier: apiResult.supplier,
                dateString: apiResult.date,
                date: parsedDate,
                amountString: apiResult.amount,
                amountCents: cents,
                reference: apiResult.reference,
                category: apiResult.category,
                sourceFile: url,
                importState: .pending
            ))
        } catch {
            results.append(ExtractedReceipt(
                itemName: url.lastPathComponent, supplier: "", dateString: "",
                date: .now, amountString: "", amountCents: 0, reference: "",
                category: "Other", sourceFile: url,
                importState: .failed(error.localizedDescription)
            ))
        }
    }

    return results
}

// MARK: - Single-File Processing (for queue-based import)

func processSingleFile(
    url: URL,
    apiKey: String,
    model: String,
    maxTokens: Int,
    categories: [String] = [],
    hint: String? = nil,
    onStateChange: @escaping (QueueItemState) -> Void
) async -> Result<ExtractedReceipt, Error> {
    let cats = categories.isEmpty ? loadCategories() : categories
    onStateChange(.extracting)
    do {
        let text = try await extractText(from: url)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(NSError(domain: "ReceiptProcessor", code: 8,
                userInfo: [NSLocalizedDescriptionKey: "No text could be extracted from this file"]))
        }
        onStateChange(.calling)
        let apiResult = try await callOpenRouter(text: text, apiKey: apiKey, model: model, maxTokens: maxTokens, categories: cats, hint: hint)
        let receipt = ExtractedReceipt(
            itemName: apiResult.item,
            supplier: apiResult.supplier,
            dateString: apiResult.date,
            date: parseReceiptDate(apiResult.date),
            amountString: apiResult.amount,
            amountCents: parseAmountCents(apiResult.amount),
            reference: apiResult.reference,
            category: apiResult.category,
            sourceFile: url,
            importState: .pending
        )
        return .success(receipt)
    } catch {
        return .failure(error)
    }
}
