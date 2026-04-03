import Foundation
import SwiftUI
import SwiftData

@main
struct AkaunApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let navigationModel = AppNavigationModel()
    private let autoImportQueue = AutoImportQueue()

    var sharedModelContainer: ModelContainer

    init() {
        try? BackupService.applyPendingRestore()
        let schema = Schema([
            Expense.self,
            Income.self,
            Claim.self,
            Attachment.self,
            ClaimAttachment.self,
            IncomeAttachment.self,
            AppSequence.self,
            ExpenseSearchData.self,
            IncomeSearchData.self,
            ClaimSearchData.self,
        ])
        try? FileManager.default.createDirectory(
            at: BackupService.appSupportURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let modelConfiguration = ModelConfiguration(schema: schema, url: BackupService.defaultStoreURL)
        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("") {
            ContentView()
                .environment(navigationModel)
                .environment(autoImportQueue)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    migrateDocumentFilenameToAttachments()
                    migrateAttachmentsToSubfolders()
                    migrateExpenseSearchData()
                    migrateIncomeSearchData()
                    migrateClaimSearchData()
                    let ctx = sharedModelContainer.mainContext
                    Task { await autoImportQueue.startupHintCheckIfNeeded(in: ctx) }
                }
        }
        .modelContainer(sharedModelContainer)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button {
                    SettingsWindowController.show(modelContainer: sharedModelContainer)
                } label: {
                    Label("Settings…", systemImage: "gear")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    private func migrateAttachmentsToSubfolders() {
        let context = sharedModelContainer.mainContext

        // 1. Attachment records: move expense attachments → Expenses/, claim attachments → Claims/
        if let allAttachments = try? context.fetch(FetchDescriptor<Attachment>()) {
            var migrated = false
            for attachment in allAttachments {
                guard !attachment.filename.contains("/") else { continue }
                let subfolder: String
                if attachment.claim != nil {
                    subfolder = "Claims"
                } else {
                    subfolder = "Expenses"
                }
                let oldURL = DocumentStore.url(for: attachment.filename)
                let newName = subfolder + "/" + attachment.filename
                let newURL = DocumentStore.url(for: newName)
                try? FileManager.default.createDirectory(
                    at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? FileManager.default.moveItem(at: oldURL, to: newURL)) != nil {
                    attachment.filename = newName
                    migrated = true
                }
            }
            if migrated { try? context.save() }
        }

        // 2. Attachment records with claim != nil → convert to ClaimAttachment, delete old
        if let claimAttachments = try? context.fetch(FetchDescriptor<Attachment>()) {
            let toMigrate = claimAttachments.filter { $0.claim != nil }
            if !toMigrate.isEmpty {
                for old in toMigrate {
                    guard let claim = old.claim else { continue }
                    let ca = ClaimAttachment(filename: old.filename, displayName: old.displayName, addedDate: old.addedDate)
                    claim.claimAttachments.append(ca)
                    old.claim = nil
                    context.delete(old)
                }
                try? context.save()
            }
        }

        // 3. IncomeAttachment records: move to Income/
        if let incomeAttachments = try? context.fetch(FetchDescriptor<IncomeAttachment>()) {
            var migrated = false
            for attachment in incomeAttachments {
                guard !attachment.filename.contains("/") else { continue }
                let oldURL = DocumentStore.url(for: attachment.filename)
                let newName = "Income/" + attachment.filename
                let newURL = DocumentStore.url(for: newName)
                try? FileManager.default.createDirectory(
                    at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? FileManager.default.moveItem(at: oldURL, to: newURL)) != nil {
                    attachment.filename = newName
                    migrated = true
                }
            }
            if migrated { try? context.save() }
        }
    }

    private func migrateExpenseSearchData() {
        let context = sharedModelContainer.mainContext
        guard let expenses = try? context.fetch(FetchDescriptor<Expense>()) else { return }
        let needsMigration = expenses.filter { $0.searchData == nil && !$0.attachments.isEmpty }
        guard !needsMigration.isEmpty else { return }
        Task {
            for expense in needsMigration {
                await extractAndStoreSearchText(for: expense, in: context)
            }
        }
    }

    private func migrateIncomeSearchData() {
        let context = sharedModelContainer.mainContext
        guard let incomes = try? context.fetch(FetchDescriptor<Income>()) else { return }
        let needsMigration = incomes.filter { $0.searchData == nil && !$0.attachments.isEmpty }
        guard !needsMigration.isEmpty else { return }
        Task {
            for income in needsMigration {
                await extractAndStoreSearchText(for: income, in: context)
            }
        }
    }

    private func migrateClaimSearchData() {
        let context = sharedModelContainer.mainContext
        guard let claims = try? context.fetch(FetchDescriptor<Claim>()) else { return }
        let needsMigration = claims.filter { $0.searchData == nil && !$0.claimAttachments.isEmpty }
        guard !needsMigration.isEmpty else { return }
        Task {
            for claim in needsMigration {
                await extractAndStoreSearchText(for: claim, in: context)
            }
        }
    }

    private func migrateDocumentFilenameToAttachments() {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Expense>()
        guard let expenses = try? context.fetch(descriptor) else { return }
        var migrated = false
        for expense in expenses {
            guard let filename = expense.documentFilename, !filename.isEmpty, expense.attachments.isEmpty else { continue }
            let display = DocumentStore.displayName(for: filename)
            let attachment = Attachment(filename: filename, displayName: display, addedDate: expense.date)
            expense.attachments.append(attachment)
            expense.documentFilename = nil
            migrated = true
        }
        if migrated {
            try? context.save()
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Close duplicate windows left over from macOS window state restoration.
        let visible = NSApp.windows.filter { $0.canBecomeKey && $0.isVisible }
        visible.dropFirst().forEach { $0.close() }

        // Prevent future state restoration from recreating duplicates.
        NSApp.windows.forEach { $0.isRestorable = false }
    }
}
