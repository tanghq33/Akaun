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
                .onAppear { migrateDocumentFilenameToAttachments() }
        }
        .modelContainer(sharedModelContainer)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    SettingsWindowController.show(modelContainer: sharedModelContainer)
                }
                .keyboardShortcut(",", modifiers: .command)
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
