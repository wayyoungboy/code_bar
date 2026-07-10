import Foundation

/// File-backed storage for CodeBar configuration data.
final class CodeBarFileStore {
    static let shared = CodeBarFileStore()

    private let fileManager: FileManager
    let rootDirectory: URL

    init(
        rootDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".code_bar", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    func save(_ data: Data, for key: String) throws {
        try ensureRootDirectory()
        let url = fileURL(for: key)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }

    func read(for key: String) throws -> Data {
        try Data(contentsOf: fileURL(for: key))
    }

    func delete(_ key: String) throws {
        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func exists(_ key: String) -> Bool {
        fileManager.fileExists(atPath: fileURL(for: key).path)
    }

    func save<T: Codable>(_ object: T, for key: String) throws {
        let data = try JSONEncoder().encode(object)
        try save(data, for: key)
    }

    func read<T: Codable>(_ type: T.Type, for key: String) throws -> T {
        let data = try read(for: key)
        return try JSONDecoder().decode(type, from: data)
    }

    func readIfPresent<T: Codable>(_ type: T.Type, for key: String) -> T? {
        try? read(type, for: key)
    }

    func fileURL(for key: String) -> URL {
        rootDirectory.appendingPathComponent("\(sanitizedFileName(for: key)).json")
    }

    private func ensureRootDirectory() throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
    }

    private func sanitizedFileName(for key: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = key.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let fileName = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return fileName.isEmpty ? "data" : fileName
    }
}
