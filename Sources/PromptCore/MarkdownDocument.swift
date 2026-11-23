import Foundation

/// The library owns the content. External paths are never persisted or followed.
public struct MarkdownDocument: Codable, Hashable {
    public var fileName: String
    public var data: Data
    public init(fileName: String, data: Data) throws {
        self.fileName = fileName; self.data = data
        try validate()
    }
    public static func isSupported(_ url: URL) -> Bool {
        url.isFileURL && ["md", "markdown"].contains(url.pathExtension.lowercased())
    }
    public static func read(_ url: URL) throws -> MarkdownDocument {
        guard isSupported(url) else { throw LibraryError.invalid("请选择 .md 或 .markdown 文件。") }
        let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard attributes.isRegularFile == true, let size = attributes.fileSize, size <= 20_000_000 else {
            throw LibraryError.invalid("Markdown 文件必须为不超过 20 MB 的常规文件。")
        }
        return try MarkdownDocument(fileName: url.lastPathComponent, data: Data(contentsOf: url))
    }
    public var text: String {
        get throws {
            // BOMs are removed from the editable body, while the initial copy keeps exact bytes.
            if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
               let value = String(data: data, encoding: .utf16), !value.contains("\0") { return value }
            var bytes = data
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
            guard let value = String(data: bytes, encoding: .utf8), !value.contains("\0") else {
                throw LibraryError.invalid("无法读取文件编码。请将 Markdown 保存为 UTF-8 或带 BOM 的 UTF-16。")
            }
            return value
        }
    }
    public var title: String { String(URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent.prefix(120)) }
    public func validate() throws {
        guard !fileName.isEmpty, fileName.count <= 240,
              !fileName.contains("/"), !fileName.contains("\\"), !fileName.contains(":"),
              !fileName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              Self.isSupported(URL(fileURLWithPath: fileName)), data.count <= 20_000_000 else {
            throw LibraryError.invalid("Markdown 文件名或文件大小无效。")
        }
        let body = try text
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, body.utf8.count <= 20_000_000 else {
            throw LibraryError.invalid("Markdown 正文为空或超过 20 MB。")
        }
    }
    public mutating func updateBody(_ body: String) throws {
        let old = data; data = Data(body.utf8)
        do { try validate() } catch { data = old; throw error }
    }
    /// A distinct directory per prompt prevents same-name documents from overwriting each other.
    public func materialize(in directory: URL, promptID: UUID) throws -> URL {
        try validate()
        let folder = directory.appendingPathComponent(promptID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName, isDirectory: false)
        if (try? Data(contentsOf: url)) != data { try data.write(to: url, options: .atomic) }
        return url
    }
}
