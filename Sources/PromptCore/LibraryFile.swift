import Foundation
import CryptoKit

/// A version-independent directory owns immutable text / Markdown files and a compact manifest.
public final class LibraryFile: @unchecked Sendable {
    public let url: URL
    public var backupURL: URL { url.deletingPathExtension().appendingPathExtension("backup.json") }
    public var documentsURL: URL { url.deletingLastPathComponent().appendingPathComponent("Documents", isDirectory: true) }
    private let lock = NSLock()
    private var previousData: Data?
    private var repairingPrimary = false
    private var cache: [UUID: Cached] = [:]
    private struct Cached { var prompt: Prompt; var body: Asset; var markdown: [Document] }
    private struct Asset: Codable { var path: String; var bytes: Int; var sha256: String }
    private struct Document: Codable { var fileName: String; var asset: Asset }
    private struct Record: Codable { var metadata: Prompt; var body: Asset; var markdown: [Document] }
    private struct Manifest: Codable {
        var storageVersion = 1
        var version: Int
        var categories: [PromptCategory]
        var preferences: Preferences
        var prompts: [Record]
    }
    public init(url: URL) { self.url = url }
    static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; e.dateEncodingStrategy = .iso8601; return e
    }
    public static func decode(_ data: Data) throws -> PromptLibrary {
        guard data.count <= 512_000_000 else { throw LibraryError.invalid("导入文件超过 512 MB。") }
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        var library = try decoder().decode(PromptLibrary.self, from: LegacyLibrary.adapt(data, root: root))
        try library.validate(); library.version = 3
        return library
    }
    public static func encode(_ library: PromptLibrary) throws -> Data {
        try library.validate()
        let data = try encoder().encode(library)
        guard data.count <= 512_000_000 else { throw LibraryError.invalid("导出资料库超过 512 MB。") }
        return data
    }
    public func load() throws -> PromptLibrary? {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url), library = try restore(data)
        previousData = data; repairingPrimary = false; return library
    }
    public func loadBackup() throws -> PromptLibrary {
        lock.lock(); defer { lock.unlock() }
        let data = try Data(contentsOf: backupURL), library = try restore(data)
        previousData = data; repairingPrimary = true; return library
    }
    private func restore(_ data: Data) throws -> PromptLibrary {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard root?["storageVersion"] != nil else { return try Self.decode(data) }
        let manifestDecoder = Self.decoder(); manifestDecoder.dateDecodingStrategy = .deferredToDate
        let manifest = try manifestDecoder.decode(Manifest.self, from: data)
        guard manifest.storageVersion == 1 else { throw LibraryError.invalid("此资料库由更新的版本创建，请升级词屿。") }
        guard manifest.prompts.count <= 50_000,
              manifest.prompts.allSatisfy({ record in
                  record.markdown.count <= 20 && ([record.body] + record.markdown.map(\.asset)).allSatisfy { (0...20_000_000).contains($0.bytes) }
              }),
              manifest.prompts.reduce(0, { $0 + $1.body.bytes + $1.markdown.reduce(0, { $0 + $1.asset.bytes }) }) <= 512_000_000 else {
            throw LibraryError.invalid("资料库内容超过 512 MB。")
        }
        var restored: [Prompt] = [], fresh: [UUID: Cached] = [:]
        for record in manifest.prompts {
            var prompt = record.metadata
            guard let body = String(data: try read(record.body), encoding: .utf8) else { throw LibraryError.invalid("本地正文编码无效。") }
            prompt.body = body
            let docs = try record.markdown.map { try MarkdownDocument(fileName: $0.fileName, data: read($0.asset)) }
            prompt.markdown = docs.first; prompt.additionalMarkdown = docs.count > 1 ? Array(docs.dropFirst()) : nil
            restored.append(prompt); fresh[prompt.id] = Cached(prompt: prompt, body: record.body, markdown: record.markdown)
        }
        var library = PromptLibrary(categories: manifest.categories, prompts: restored, preferences: manifest.preferences)
        library.version = manifest.version; try library.validate(); cache = fresh
        return library
    }
    private func assetURL(_ asset: Asset) throws -> URL {
        let components = asset.path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.first == "Documents", components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !asset.path.contains("\\"), asset.bytes >= 0, asset.bytes <= 20_000_000, asset.sha256.count == 64 else {
            throw LibraryError.invalid("本地文件路径或大小无效。")
        }
        let root = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let resolved = root.appendingPathComponent(asset.path).resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(root.appendingPathComponent("Documents").path + "/") else { throw LibraryError.invalid("本地文件不在词屿资料库中。") }
        return resolved
    }
    private func read(_ asset: Asset) throws -> Data {
        let location = try assetURL(asset)
        guard let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize, size == asset.bytes else { throw LibraryError.invalid("本地文件缺失或不完整：\(location.lastPathComponent)") }
        let data = try Data(contentsOf: location)
        guard Self.digest(data) == asset.sha256 else { throw LibraryError.invalid("本地文件校验失败：\(location.lastPathComponent)") }
        return data
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func persist(_ data: Data, promptID: UUID, name: String, index: Int? = nil) throws -> Asset {
        let hash = Self.digest(data)
        let path = index.map { "Documents/\(promptID.uuidString)/attachment-\($0)-\(hash)/\(name)" } ?? "Documents/\(promptID.uuidString)/body-\(hash).txt"
        let asset = Asset(path: path, bytes: data.count, sha256: hash), destination = try assetURL(asset)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            guard try Data(contentsOf: destination) == data else { throw LibraryError.invalid("已有文件校验失败，已暂停保存。") }
        } else { try data.write(to: destination, options: .atomic) }
        return asset
    }
    public func save(_ library: PromptLibrary) throws {
        lock.lock(); defer { lock.unlock() }
        try library.validate(checkContent: false)
        if !repairingPrimary, let previousData, let current = try? Data(contentsOf: url), current != previousData {
            throw LibraryError.invalid("资料库已被其他进程修改，已暂停写入。请重新打开词屿后重试。")
        }
        // Never overwrite an unreadable primary file unless a verified backup was explicitly loaded.
        if previousData == nil, let existing = try? Data(contentsOf: url) { _ = try restore(existing); previousData = existing }
        var records: [Record] = [], fresh: [UUID: Cached] = [:]
        for prompt in library.prompts {
            let prior = cache[prompt.id]
            let body: Asset
            if let prior, prior.prompt.body == prompt.body { body = prior.body }
            else { try prompt.validateContent(); body = try persist(Data(prompt.body.utf8), promptID: prompt.id, name: "body.txt") }
            let documents: [Document]
            if let prior, prior.prompt.markdownDocuments == prompt.markdownDocuments { documents = prior.markdown }
            else {
                documents = try prompt.markdownDocuments.enumerated().map { i, document in
                    try document.validate()
                    return try Document(fileName: document.fileName, asset: persist(document.data, promptID: prompt.id, name: document.fileName, index: i))
                }
            }
            var metadata = prompt; metadata.body = ""; metadata.markdown = nil; metadata.additionalMarkdown = nil
            records.append(Record(metadata: metadata, body: body, markdown: documents))
            fresh[prompt.id] = Cached(prompt: prompt, body: body, markdown: documents)
        }
        let manifestEncoder = Self.encoder(); manifestEncoder.dateEncodingStrategy = .deferredToDate
        guard records.reduce(0, { $0 + $1.body.bytes + $1.markdown.reduce(0, { $0 + $1.asset.bytes }) }) <= 512_000_000 else { throw LibraryError.invalid("资料库内容超过 512 MB。") }
        let data = try manifestEncoder.encode(Manifest(version: 3, categories: library.categories, preferences: library.preferences, prompts: records))
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if repairingPrimary, let current = try? Data(contentsOf: url), current != previousData {
            let recovery = directory.appendingPathComponent("Recovery", isDirectory: true)
            try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
            try current.write(to: recovery.appendingPathComponent("library-\(UUID().uuidString).json"), options: .atomic)
        }
        if let previous = previousData {
            let root = (try? JSONSerialization.jsonObject(with: previous)) as? [String: Any]
            if root?["storageVersion"] == nil {
                let migrations = directory.appendingPathComponent("Migrations", isDirectory: true)
                try FileManager.default.createDirectory(at: migrations, withIntermediateDirectories: true)
                try previous.write(to: migrations.appendingPathComponent("library-\(UUID().uuidString).json"), options: .atomic)
            }
            try previous.write(to: backupURL, options: .atomic)
        }
        try data.write(to: url, options: .atomic); previousData = data; cache = fresh; repairingPrimary = false
    }
    public func markdownURL(for prompt: Prompt, document: MarkdownDocument) throws -> URL {
        try document.validate()
        return try assetURL(persist(document.data, promptID: prompt.id, name: document.fileName, index: prompt.markdownDocuments.firstIndex(of: document) ?? 0))
    }
}

public actor LibraryDisk {
    private let file: LibraryFile
    private var savedRevision = -1
    public init(file: LibraryFile) { self.file = file }
    public func load() throws -> (PromptLibrary, Bool) {
        do {
            if let library = try file.load() { try file.save(library); return (library, false) }
            if FileManager.default.fileExists(atPath: file.backupURL.path) { let backup = try file.loadBackup(); try file.save(backup); return (backup, true) }
            let library = PromptLibrary.seed; try file.save(library); return (library, false)
        } catch { let backup = try file.loadBackup(); try file.save(backup); return (backup, true) }
    }
    public func save(_ library: PromptLibrary, revision: Int) throws {
        guard revision > savedRevision else { return }
        try file.save(library); savedRevision = revision
    }
}
