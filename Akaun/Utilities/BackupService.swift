import Foundation
import SwiftData
import AppKit

enum BackupService {

    // MARK: - Nested types

    struct BackupManifest: Codable {
        let version: Int
        let date: String
        let appVersion: String
        let appBuild: String
    }

    struct BackupSettings: Codable {
        let categories: [String]
        let incomeCategories: [String]
        let autoImportModel: String
        let autoImportMaxTokens: Int
        let autoImportShowFreeOnly: Bool
        let autoImportApiKey: String

        enum CodingKeys: String, CodingKey {
            case categories, incomeCategories, autoImportModel, autoImportMaxTokens, autoImportShowFreeOnly, autoImportApiKey
        }

        init(categories: [String], incomeCategories: [String], autoImportModel: String, autoImportMaxTokens: Int, autoImportShowFreeOnly: Bool, autoImportApiKey: String) {
            self.categories = categories
            self.incomeCategories = incomeCategories
            self.autoImportModel = autoImportModel
            self.autoImportMaxTokens = autoImportMaxTokens
            self.autoImportShowFreeOnly = autoImportShowFreeOnly
            self.autoImportApiKey = autoImportApiKey
        }

        // Custom decoder so older backups without incomeCategories can still be restored
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            categories = try c.decode([String].self, forKey: .categories)
            incomeCategories = (try? c.decode([String].self, forKey: .incomeCategories)) ?? []
            autoImportModel = try c.decode(String.self, forKey: .autoImportModel)
            autoImportMaxTokens = try c.decode(Int.self, forKey: .autoImportMaxTokens)
            autoImportShowFreeOnly = try c.decode(Bool.self, forKey: .autoImportShowFreeOnly)
            autoImportApiKey = try c.decode(String.self, forKey: .autoImportApiKey)
        }
    }

    enum BackupError: LocalizedError {
        case noStoreFound
        case manifestMissing
        case versionUnsupported(Int)
        case copyFailed(Error)
        case stagingAlreadyPending

        var errorDescription: String? {
            switch self {
            case .noStoreFound:
                return "Could not locate the SwiftData store file."
            case .manifestMissing:
                return "The selected backup is missing its manifest file and may be corrupt."
            case .versionUnsupported(let v):
                return "This backup was created with a newer version of Akaun (format \(v)) and cannot be restored."
            case .copyFailed(let error):
                return "A file copy operation failed: \(error.localizedDescription)"
            case .stagingAlreadyPending:
                return "A restore is already staged. Please restart the app to apply it."
            }
        }
    }

    // MARK: - Private URL helpers

    static var appSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Akaun", isDirectory: true)
    }

    static var defaultStoreURL: URL {
        appSupportURL.appendingPathComponent("default.store")
    }

    private static var stagingURL: URL {
        appSupportURL.appendingPathComponent("RestoreStaging", isDirectory: true)
    }

    private static var stagingFlagURL: URL {
        stagingURL.appendingPathComponent(".restore_pending")
    }

    private static var documentsURL: URL {
        appSupportURL.appendingPathComponent("Documents", isDirectory: true)
    }

    // MARK: - Public API

    static func storeURL(from container: ModelContainer) -> URL {
        if let url = container.configurations.first?.url {
            return url
        }
        return appSupportURL.appendingPathComponent("default.store")
    }

    static func createBackup(to destinationURL: URL, modelContainer: ModelContainer) throws {
        let accessing = destinationURL.startAccessingSecurityScopedResource()
        defer { if accessing { destinationURL.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default

        // Remove existing package if present, then create fresh
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try fm.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let dbDir = destinationURL.appendingPathComponent("database", isDirectory: true)
        let docsDir = destinationURL.appendingPathComponent("documents", isDirectory: true)
        try fm.createDirectory(at: dbDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: docsDir, withIntermediateDirectories: true)

        // Copy store files
        let storeURL = storeURL(from: modelContainer)
        let storeBase = storeURL.deletingPathExtension().lastPathComponent
        let storeSuffixes = ["store", "store-wal", "store-shm"]
        for suffix in storeSuffixes {
            let src = storeURL.deletingLastPathComponent()
                .appendingPathComponent("\(storeBase).\(suffix)")
            if fm.fileExists(atPath: src.path) {
                let dst = dbDir.appendingPathComponent("\(storeBase).\(suffix)")
                do {
                    try fm.copyItem(at: src, to: dst)
                } catch {
                    throw BackupError.copyFailed(error)
                }
            }
        }

        // Copy documents
        let docContents = (try? fm.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)) ?? []
        for fileURL in docContents {
            guard fileURL.lastPathComponent != ".DS_Store" else { continue }
            let dst = docsDir.appendingPathComponent(fileURL.lastPathComponent)
            do {
                try fm.copyItem(at: fileURL, to: dst)
            } catch {
                throw BackupError.copyFailed(error)
            }
        }

        // Write settings.json
        let ud = UserDefaults.standard
        let settings = BackupSettings(
            categories: ud.stringArray(forKey: "expense.categories") ?? [],
            incomeCategories: ud.stringArray(forKey: "income.categories") ?? [],
            autoImportModel: ud.string(forKey: "autoImport.model") ?? "",
            autoImportMaxTokens: ud.integer(forKey: "autoImport.maxTokens"),
            autoImportShowFreeOnly: ud.bool(forKey: "autoImport.showFreeOnly"),
            autoImportApiKey: ud.string(forKey: "autoImport.apiKey") ?? ""
        )
        let settingsData = try JSONEncoder().encode(settings)
        try settingsData.write(to: destinationURL.appendingPathComponent("settings.json"))

        // Write manifest.json
        let info = Bundle.main.infoDictionary
        let manifest = BackupManifest(
            version: 1,
            date: ISO8601DateFormatter().string(from: Date.now),
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "1.0",
            appBuild: info?["CFBundleVersion"] as? String ?? "1"
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: destinationURL.appendingPathComponent("manifest.json"))

        // Record last backup date
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "backup.lastBackupDate")
    }

    static func stageRestore(from sourceURL: URL) throws {
        guard !hasPendingRestore() else { throw BackupError.stagingAlreadyPending }

        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default

        // Validate manifest
        let manifestURL = sourceURL.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL) else {
            throw BackupError.manifestMissing
        }
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: manifestData)
        guard manifest.version == 1 else {
            throw BackupError.versionUnsupported(manifest.version)
        }

        // Prepare staging
        if fm.fileExists(atPath: stagingURL.path) {
            try fm.removeItem(at: stagingURL)
        }
        try fm.createDirectory(at: stagingURL, withIntermediateDirectories: true)

        // Copy database, documents, settings.json into staging
        // Clean up staging directory if any step fails, so no orphaned staging is left behind
        do {
            let items = ["database", "documents", "settings.json"]
            for item in items {
                let src = sourceURL.appendingPathComponent(item)
                let dst = stagingURL.appendingPathComponent(item)
                if fm.fileExists(atPath: src.path) {
                    try fm.copyItem(at: src, to: dst)
                }
            }

            // Write pending flag
            try "1".write(to: stagingFlagURL, atomically: true, encoding: .utf8)
        } catch {
            try? fm.removeItem(at: stagingURL)
            throw BackupError.copyFailed(error)
        }
    }

    static func hasPendingRestore() -> Bool {
        FileManager.default.fileExists(atPath: stagingFlagURL.path)
    }

    static func applyPendingRestore() throws {
        guard hasPendingRestore() else { return }

        let fm = FileManager.default

        // Apply settings
        let settingsURL = stagingURL.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: settingsURL),
           let settings = try? JSONDecoder().decode(BackupSettings.self, from: data) {
            let ud = UserDefaults.standard
            ud.set(settings.categories, forKey: "expense.categories")
            if !settings.incomeCategories.isEmpty {
                ud.set(settings.incomeCategories, forKey: "income.categories")
            }
            ud.set(settings.autoImportModel, forKey: "autoImport.model")
            ud.set(settings.autoImportMaxTokens, forKey: "autoImport.maxTokens")
            ud.set(settings.autoImportShowFreeOnly, forKey: "autoImport.showFreeOnly")
            ud.set(settings.autoImportApiKey, forKey: "autoImport.apiKey")
        }

        // Replace documents folder
        if fm.fileExists(atPath: documentsURL.path) {
            try fm.removeItem(at: documentsURL)
        }
        let stagedDocs = stagingURL.appendingPathComponent("documents")
        if fm.fileExists(atPath: stagedDocs.path) {
            try fm.copyItem(at: stagedDocs, to: documentsURL)
        }

        // Replace store files
        let stagedDB = stagingURL.appendingPathComponent("database")
        if fm.fileExists(atPath: stagedDB.path) {
            try fm.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            // Remove existing store files
            let storeNames = ["default.store", "default.store-wal", "default.store-shm"]
            for name in storeNames {
                let existing = appSupportURL.appendingPathComponent(name)
                if fm.fileExists(atPath: existing.path) {
                    try fm.removeItem(at: existing)
                }
            }
            // Copy staged database files
            let dbFiles = (try? fm.contentsOfDirectory(at: stagedDB, includingPropertiesForKeys: nil)) ?? []
            for fileURL in dbFiles {
                let dst = appSupportURL.appendingPathComponent(fileURL.lastPathComponent)
                try fm.copyItem(at: fileURL, to: dst)
            }
        }

        // Remove staging (cleans flag too)
        try fm.removeItem(at: stagingURL)
    }

    static func restartApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
