# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Akaun.xcodeproj \
  -scheme Akaun \
  -destination "platform=macOS" \
  build
```

`xcode-select` points to CommandLineTools, not Xcode — always use the full path above. There are no automated tests.

## Environment

- Xcode 26.3, macOS 26.2 SDK, Swift 5, target `arm64-apple-macos26.2`
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — all top-level code is implicitly `@MainActor`
- `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` — every symbol must be explicitly imported; transitive imports are not sufficient
- App sandbox enabled; `ENABLE_USER_SELECTED_FILES = readonly`
- Project uses `PBXFileSystemSynchronizedRootGroup` — files on disk are auto-included; no manual `.pbxproj` editing needed

## Architecture

### Data layer — SwiftData

Four `@Model` types registered in `AkaunApp.swift`:

| Model | Key fields |
|---|---|
| `Expense` | `expenseNumber`, `itemName`, `supplier`, `date`, `amountCents: Int`, `reference`, `status: ExpenseStatus`, `documentFilename: String?`, `remark`, `category` (default `"Other"`), `claim: Claim?` |
| `Income` | `incomeNumber`, `date`, `amountCents: Int`, `remark` — running number prefix `"IN"` |
| `Claim` | `claimNumber`, `date`, `status: ClaimStatus`, `expenses: [Expense]` (`.nullify` delete rule), computed `totalAmountCents` |
| `AppSequence` | `prefix`, `dateKey`, `lastSequence` — backing store for running numbers |

**Critical:** All monetary amounts are stored as `amountCents: Int`. Never use `Decimal` or `Double` for amounts — SwiftData loses precision with those types.

**`#Predicate` limitation:** Enum comparisons against string literals do not compile. Use in-memory filtering instead.

### Running numbers

`RunningNumberGenerator.next(prefix:for:in:)` generates sequential IDs of the form `EX20260312-001`. Numbers are assigned at save time (not at form-open time). Call this inside the same `ModelContext` operation that inserts the record.

### Document storage

`DocumentStore` copies attached files into `~/Library/Application Support/Akaun/Documents/` with a UUID prefix. `Expense.documentFilename` stores only the filename, not the full path. Use `DocumentStore.url(for:)` to reconstruct the full URL at display time.

### Navigation

`AppNavigationModel` (`@Observable`) holds the current sidebar section and the selected `PersistentIdentifier` for each section. Both `AppNavigationModel` and `AutoImportQueue` are injected via `.environment()` in `AkaunApp` and consumed with `@Environment` in views.

`ContentView` renders a three-column `NavigationSplitView`: `SidebarView` → section list view → detail view. The detail column resolves the selected ID by fetching from `ModelContext`.

### Settings

Settings uses an AppKit `SettingsWindowController` (`NSWindowController` + `NSTabViewController`), not SwiftUI's `Settings` scene. Panes are defined in `SettingsView.swift` as SwiftUI views wrapped in `NSHostingController`. The model container is passed explicitly to each pane.

### Formatting & categories

- Currency: MYR with `RM` symbol. Use `Formatters.formatCents(_:)` to display amounts.
- Expense categories are stored in `UserDefaults` (key `expense.categories`) via `loadCategories()` / `saveCategories()` in `CategoryStore.swift`. Default list: Food & Beverage, Transport, Accommodation, Office Supplies, Utilities, Entertainment, Medical, Other.

### Auto Import

`AutoImportQueue` (`@Observable`, not a SwiftData model) manages a queue of `AutoImportQueueItem` objects through states: `.extracting → .calling → .ready → .imported` (or `.failed`).

Processing pipeline per file:
1. `extractText(from:)` — Vision OCR for images; PDFKit + OCR fallback for scanned PDFs
2. `callOpenRouter(...)` — sends extracted text to OpenRouter API, returns structured JSON
3. `parseAmountCents` / `parseReceiptDate` — parse the API response
4. On user confirmation, `AutoImportQueue.importItem(_:in:)` calls `DocumentStore.importFile` and inserts a new `Expense` with a generated running number

OpenRouter settings (API key, model, max tokens) are stored in `UserDefaults` via `@AppStorage` and configured in `Settings → Auto Import`.

## SDK Quirks

- `.accentColor` is not a `ShapeStyle` in macOS 26.2 — use `Color.accentColor` explicitly
- `#Predicate` enum-vs-string comparisons do not compile — filter in memory instead
