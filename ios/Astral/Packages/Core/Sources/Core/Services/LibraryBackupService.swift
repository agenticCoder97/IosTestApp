import Foundation
import SQLite3
import CryptoKit

/// Versioned, verified same-app backup. SQLite's backup API includes committed WAL
/// transactions. Content uses relative paths; restore is staged until the next launch.
public enum LibraryBackupService {
    public struct Manifest: Codable {
        public var format = 1
        public var schemaVersion = 1
        public var createdAt = Date()
        public var files: [String: String]
    }
    public static var storeURL: URL { URL.applicationSupportDirectory.appendingPathComponent("default.store") }
    private static var pendingURL: URL { URL.applicationSupportDirectory.appendingPathComponent("AstralPendingRestore") }
    public static var hasPendingRestore: Bool { FileManager.default.fileExists(atPath: pendingURL.path) }

    public static func create() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Astral-\(UUID().uuidString).astralbackup")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            try snapshotDatabase(from: storeURL, to: root.appendingPathComponent("default.store"))
            if fm.fileExists(atPath: URL.documentsDirectory.path) {
                try fm.copyItem(at: URL.documentsDirectory, to: root.appendingPathComponent("Documents"))
            }
            let keys = UserDefaults.standard.dictionaryRepresentation().filter { key, _ in
                key.hasPrefix("reading.") || key.hasPrefix("comic") || key.hasPrefix("fanfic") || key.hasPrefix("reader") || ["activeContentType", "forceLandscape", "autoScrollSpeed", "hideRotateHint"].contains(key)
            }
            let prefs = try PropertyListSerialization.data(fromPropertyList: keys, format: .binary, options: 0)
            try prefs.write(to: root.appendingPathComponent("preferences.plist"), options: .atomic)
            let manifest = Manifest(files: try hashes(in: root))
            try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
            return root
        } catch { try? fm.removeItem(at: root); throw error }
    }

    public static func stageRestore(from source: URL) throws {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        try validate(source)
        let fm = FileManager.default
        let staging = pendingURL.appendingPathExtension(UUID().uuidString)
        try fm.copyItem(at: source, to: staging)
        do {
            try validate(staging)
            if fm.fileExists(atPath: pendingURL.path) { try fm.removeItem(at: pendingURL) }
            try fm.moveItem(at: staging, to: pendingURL)
        } catch { try? fm.removeItem(at: staging); throw error }
    }

    /// Called only BEFORE opening ModelContainer. Keeps a complete rollback copy.
    public static func applyPendingRestore() throws {
        guard hasPendingRestore else { return }
        try validate(pendingURL)
        let fm = FileManager.default
        let recovery = URL.applicationSupportDirectory.appendingPathComponent("AstralBeforeRestore-\(UUID().uuidString)")
        try fm.createDirectory(at: recovery, withIntermediateDirectories: true)
        var moved: [(URL, URL)] = []
        let live = [storeURL, URL(fileURLWithPath: storeURL.path + "-wal"), URL(fileURLWithPath: storeURL.path + "-shm"), URL.documentsDirectory]
        do {
            for url in live where fm.fileExists(atPath: url.path) {
                let backup = recovery.appendingPathComponent(url.lastPathComponent)
                try fm.moveItem(at: url, to: backup); moved.append((url, backup))
            }
            try fm.copyItem(at: pendingURL.appendingPathComponent("default.store"), to: storeURL)
            let docs = pendingURL.appendingPathComponent("Documents")
            if fm.fileExists(atPath: docs.path) { try fm.copyItem(at: docs, to: URL.documentsDirectory) }
            else { try fm.createDirectory(at: URL.documentsDirectory, withIntermediateDirectories: true) }
            let data = try Data(contentsOf: pendingURL.appendingPathComponent("preferences.plist"))
            if let preferences = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("reading.") || key.hasPrefix("comic") || key.hasPrefix("fanfic") || key.hasPrefix("reader") {
                    UserDefaults.standard.removeObject(forKey: key)
                }
                for (key, value) in preferences { UserDefaults.standard.set(value, forKey: key) }
            }
            try fm.removeItem(at: pendingURL)
        } catch {
            for (url, _) in moved { try? fm.removeItem(at: url) }
            for (url, backup) in moved { try? fm.moveItem(at: backup, to: url) }
            throw error
        }
    }

    public static func validate(_ root: URL) throws {
        let data = try Data(contentsOf: root.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.format == 1, manifest.schemaVersion == 1, manifest.files["default.store"] != nil, manifest.files["preferences.plist"] != nil else {
            throw BackupError.invalid("Unsupported or incomplete Astral backup.")
        }
        let actual = try hashes(in: root)
        guard actual == manifest.files else { throw BackupError.invalid("Backup files are missing, modified or unreadable.") }
        var db: OpaquePointer?
        guard sqlite3_open_v2(root.appendingPathComponent("default.store").absoluteString + "?immutable=1", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; throw BackupError.invalid("Backup database could not be opened.")
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &statement, nil) == SQLITE_OK else { throw BackupError.invalid("Backup database validation failed: " + String(cString: sqlite3_errmsg(db))) }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0), String(cString: text) == "ok" else { throw BackupError.invalid("Backup database is damaged.") }
    }

    private static func snapshotDatabase(from source: URL, to destination: URL) throws {
        var input: OpaquePointer?; var output: OpaquePointer?
        guard sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let input { sqlite3_close(input) }; throw BackupError.invalid("Library database could not be read.")
        }
        defer { sqlite3_close(input) }
        guard sqlite3_open(destination.path, &output) == SQLITE_OK else {
            if let output { sqlite3_close(output) }; throw BackupError.invalid("Backup could not be created.")
        }
        defer { sqlite3_close(output) }
        guard let backup = sqlite3_backup_init(output, "main", input, "main") else { throw BackupError.invalid("Library snapshot could not start.") }
        let result = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE else { throw BackupError.invalid("Library is busy. Finish importing and try again.") }
        guard sqlite3_exec(output, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else {
            throw BackupError.invalid("Library snapshot could not be finalized.")
        }
    }

    private static func hashes(in root: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        func visit(_ directory: URL, prefix: String) throws {
            let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            for url in children {
                let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
                guard attributes.isSymbolicLink != true else { throw BackupError.invalid("Backup contains a symbolic link.") }
                let path = prefix + url.lastPathComponent
                if attributes.isDirectory == true { try visit(url, prefix: path + "/"); continue }
                guard attributes.isRegularFile == true else { throw BackupError.invalid("Backup contains an unsupported file.") }
                if path == "manifest.json" { continue }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                var hash = SHA256()
                while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
                result[path] = hash.finalize().map { String(format: "%02x", $0) }.joined()
            }
        }
        try visit(root, prefix: "")
        return result
    }
    public enum BackupError: LocalizedError {
        case invalid(String)
        public var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
    }
}
