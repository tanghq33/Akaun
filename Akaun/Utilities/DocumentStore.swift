import Foundation
import SwiftData

enum DocumentStore {
    private static var documentsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Akaun/Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copy a file from `source` into the app's Documents folder with a UUID prefix.
    /// Returns the stored filename (UUID + original name).
    @discardableResult
    static func importFile(from source: URL) throws -> String {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let filename = UUID().uuidString + "_" + source.lastPathComponent
        let destination = documentsURL.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: source, to: destination)
        return filename
    }

    /// Reconstruct the full URL for a stored filename.
    static func url(for filename: String) -> URL {
        documentsURL.appendingPathComponent(filename)
    }

    /// Delete a stored file by filename.
    static func deleteFile(named filename: String) {
        let fileURL = documentsURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Strip the UUID prefix to recover the original filename for display.
    static func displayName(for filename: String) -> String {
        let parts = filename.components(separatedBy: "_")
        guard parts.count > 1 else { return filename }
        return parts.dropFirst().joined(separator: "_")
    }

    /// Delete the files backing an array of Attachments.
    static func deleteFiles(for attachments: [Attachment]) {
        for attachment in attachments {
            deleteFile(named: attachment.filename)
        }
    }

    /// Remove all files from the app's Documents directory.
    static func removeAllDocuments() {
        let dir = documentsURL
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return }
        for fileURL in contents {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
