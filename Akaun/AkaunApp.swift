import Foundation
import SwiftUI
import SwiftData

@main
struct AkaunApp: App {
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
