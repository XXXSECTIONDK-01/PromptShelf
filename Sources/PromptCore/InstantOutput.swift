import Foundation

/// Ephemeral text for a single insertion. No library or attachment is mutated.
public struct InstantDraft: Equatable {
    public let sourceID: UUID
    public let title: String
    public var body: String
    public init(prompt: Prompt) { sourceID = prompt.id; title = prompt.title; body = prompt.body }
    public var canSubmit: Bool { body.unicodeScalars.contains(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }) && body.utf8.count <= 20_000_000 }
    public func validatedBody() throws -> String {
        guard canSubmit else { throw LibraryError.invalid("正文不能为空，且不能超过 20 MB。") }
        return body
    }
}

public enum InstantOutput {
    public static func markdownDocuments(for prompt: Prompt) throws -> [MarkdownDocument] {
        if !prompt.markdownDocuments.isEmpty {
            for document in prompt.markdownDocuments { try document.validate() }
            return prompt.markdownDocuments
        }
        let invalid = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        var base = String(prompt.title.unicodeScalars.map { invalid.contains($0) ? "_" : String($0) }.joined())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.lowercased().hasSuffix(".markdown") { base = String(base.dropLast(9)) }
        else if base.lowercased().hasSuffix(".md") { base = String(base.dropLast(3)) }
        while base.utf8.count > 180 { base.removeLast() }
        while base.first == "." { base.removeFirst() }
        if base.isEmpty { base = "提示词" }
        return [try MarkdownDocument(fileName: base + ".md", data: Data(prompt.body.utf8))]
    }
    public static func materialize(_ documents: [MarkdownDocument], in root: URL, now: Date = Date()) throws -> [URL] {
        guard !documents.isEmpty, documents.count <= 20 else { throw LibraryError.invalid("Markdown 文件数量无效。") }
        for document in documents { try document.validate() }
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Keep files alive for deferred paste recipients. Remove only this cache's
        // expired session directories; never delete external or library files.
        let existing = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey, .isSymbolicLinkKey])) ?? []
        for folder in existing where UUID(uuidString: folder.lastPathComponent) != nil {
            if let values = try? folder.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey, .isSymbolicLinkKey]),
               values.isDirectory == true, values.isSymbolicLink != true,
               let created = values.creationDate, now.timeIntervalSince(created) > 86_400 {
                try? manager.removeItem(at: folder)
            }
        }
        let session = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: session, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do { return try documents.map { try $0.materialize(in: session, promptID: UUID()) } }
        catch { try? manager.removeItem(at: session); throw error }
    }
}
