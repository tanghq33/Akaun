import Foundation
import SwiftData

enum DocumentStore {
    private static var documentsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Akaun/Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copy a file from `source` into the app's Documents folder (optionally into a subfolder) with a UUID prefix.
    /// Returns the stored path relative to Documents (e.g. "Expenses/UUID_name.pdf").
    @discardableResult
    static func importFile(from source: URL, subfolder: String = "") throws -> String {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let filename = UUID().uuidString + "_" + source.lastPathComponent
        let storedName = subfolder.isEmpty ? filename : subfolder + "/" + filename
        let destination = documentsURL.appendingPathComponent(storedName)
        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
        return storedName
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

    /// Strip the subfolder prefix and UUID to recover the original filename for display.
    static func displayName(for filename: String) -> String {
        let base = (filename as NSString).lastPathComponent
        let parts = base.components(separatedBy: "_")
        guard parts.count > 1 else { return base }
        return parts.dropFirst().joined(separator: "_")
    }

    /// Delete the files backing an array of Attachments.
    static func deleteFiles(for attachments: [Attachment]) {
        for attachment in attachments {
            deleteFile(named: attachment.filename)
        }
    }

    /// Delete the files backing an array of ClaimAttachments.
    static func deleteFiles(for attachments: [ClaimAttachment]) {
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
