import AppKit
import SwiftUI
import SwiftData

final class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    static func show(modelContainer: ModelContainer) {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let controller = SettingsWindowController(modelContainer: modelContainer)
        shared = controller
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    init(modelContainer: ModelContainer) {
        let tabVC = SettingsTabViewController()
        tabVC.tabStyle = .toolbar

        let tabs: [(String, String, AnyView)] = [
            ("Intelligence", "sparkles",      AnyView(IntelligencePane())),
            ("Categories",   "tag",           AnyView(CategoriesPane())),
            ("Backup",      "externaldrive.badge.timemachine", AnyView(BackupPane(modelContainer: modelContainer))),
            ("Reset",       "arrow.counterclockwise", AnyView(ResetPane())),
            ("Advanced",    "gearshape.2",    AnyView(AdvancedPane())),
        ]

        for (title, icon, view) in tabs {
            let hosting = NSHostingController(
                rootView: view.modelContainer(modelContainer)
            )
            hosting.title = title
            let item = NSTabViewItem(viewController: hosting)
            item.label = title
            item.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
            tabVC.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabVC)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = tabVC.tabViewItems[tabVC.selectedTabViewItemIndex].label
        window.minSize = NSSize(width: 660, height: 420)

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}

private final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        view.window?.title = tabViewItem?.label ?? "Settings"
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.title = tabViewItems[selectedTabViewItemIndex].label
    }
}
