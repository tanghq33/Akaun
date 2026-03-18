import SwiftUI
import SwiftData

@main
struct AkaunApp: App {
    private let navigationModel = AppNavigationModel()
    private let autoImportQueue = AutoImportQueue()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Expense.self,
            Income.self,
            Claim.self,
            AppSequence.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup("") {
            ContentView()
                .environment(navigationModel)
                .environment(autoImportQueue)
                .frame(minWidth: 900, minHeight: 600)
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
}
