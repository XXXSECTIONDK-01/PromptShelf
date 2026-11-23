import Foundation
import CryptoKit

public struct NotesLink: Codable, Hashable {
    public var accountID: String
    public var noteID: String
    public var remoteRevision: String
    public var localFingerprint: String
    public var exportFolderID: String?
    public var syncedAt: Date
    public init(accountID: String, noteID: String, remoteRevision: String, localFingerprint: String, exportFolderID: String? = nil, syncedAt: Date = Date()) {
        self.accountID = accountID; self.noteID = noteID; self.remoteRevision = remoteRevision
        self.localFingerprint = localFingerprint; self.exportFolderID = exportFolderID; self.syncedAt = syncedAt
    }
}
public struct NotesAccount: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}
public struct NotesFolder: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var path: String
    public init(id: String, name: String, path: String) { self.id = id; self.name = name; self.path = path }
}
public struct NotesEntry: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var modified: String
    public var locked: Bool
    public var markdownCount: Int
    public init(id: String, name: String, modified: String, locked: Bool = false, markdownCount: Int = 0) {
        self.id = id; self.name = name; self.modified = modified; self.locked = locked; self.markdownCount = markdownCount
    }
}
public struct NotesContent: Equatable {
    public var accountID: String
    public var noteID: String
    public var title: String
    public var plainText: String
    public var revision: String
    public var documents: [MarkdownDocument]
    public var folderID: String?
    public init(accountID: String, noteID: String, title: String, plainText: String, revision: String, documents: [MarkdownDocument] = [], folderID: String? = nil) {
        self.accountID = accountID; self.noteID = noteID; self.title = title; self.plainText = plainText; self.revision = revision; self.documents = documents; self.folderID = folderID
    }
    public var promptBody: String {
        var value = plainText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        // Notes includes its heading in plaintext. Remove exactly that first heading, never repeated text later in the body.
        if let line = value.split(separator: "\n", omittingEmptySubsequences: false).first,
           line.trimmingCharacters(in: .whitespaces) == title.trimmingCharacters(in: .whitespaces) {
            value = String(value.dropFirst(line.count))
            if value.first == "\n" { value.removeFirst() }
        }
        value = value.replacingOccurrences(of: "\u{fffc}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty, let first = documents.first, let text = try? first.text { return text }
        return value.isEmpty ? title : value
    }
}
public struct NotesImportReport: Equatable {
    public var added = 0
    public var updated = 0
    public var skipped = 0
    public var preserved = 0
    public init() {}
}
public enum NotesSync {
    public static func exportBaseline(_ prompt: Prompt, accountID: String) -> NotesLink? {
        guard let link = prompt.notesLink, link.accountID == accountID,
              let folder = link.exportFolderID, !folder.isEmpty,
              link.localFingerprint == fingerprint(prompt) else { return nil }
        return link
    }
    public static func fingerprint(_ prompt: Prompt) -> String {
        var hasher = SHA256()
        func append(_ data: Data) {
            hasher.update(data: Data("\(data.count):".utf8)); hasher.update(data: data)
        }
        append(Data(prompt.title.utf8)); append(Data(prompt.body.utf8))
        for document in prompt.markdownDocuments { append(Data(document.fileName.utf8)); append(document.data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func html(title: String, body: String) -> String {
        func escaped(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
        }
        let normalized = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return "<h1>\(escaped(title))</h1><pre>\(escaped(normalized))</pre>"

    }
    /// Apply a whole selected batch atomically. A locally edited version is copied before pulling a newer note.
    public static func importContents(_ contents: [NotesContent], categoryID: UUID, into library: inout PromptLibrary) throws -> NotesImportReport {
        guard library.categories.contains(where: { $0.id == categoryID }), contents.count <= 20 else {
            throw LibraryError.invalid("请选择有效分类，单次最多同步 20 条备忘录。")
        }
        var next = library, report = NotesImportReport()
        for content in contents {
            guard !content.accountID.isEmpty, !content.noteID.isEmpty, content.documents.count <= 20 else {
                throw LibraryError.invalid("备忘录关联或附件数量无效。")
            }
            for document in content.documents { try document.validate() }
            let title = String(content.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
            let cleanTitle = title.isEmpty ? "未命名备忘录" : title
            if let i = next.prompts.firstIndex(where: { $0.notesLink?.accountID == content.accountID && $0.notesLink?.noteID == content.noteID }) {
                let existing = next.prompts[i]
                if existing.notesLink?.remoteRevision == content.revision { report.skipped += 1; continue }
                if existing.notesLink?.localFingerprint != fingerprint(existing) {
                    var copy = existing; copy.id = UUID(); copy.title = String(existing.title.prefix(112)) + " · 本地副本"
                    copy.notesLink = nil; copy.createdAt = Date(); copy.updatedAt = Date(); copy.lastUsedAt = nil; copy.useCount = 0
                    next.prompts.append(copy); report.preserved += 1
                }
                next.prompts[i].title = cleanTitle; next.prompts[i].body = content.promptBody
                next.prompts[i].markdown = content.documents.first
                next.prompts[i].additionalMarkdown = content.documents.count > 1 ? Array(content.documents.dropFirst()) : nil
                next.prompts[i].syncMarkdownBody = false; next.prompts[i].updatedAt = Date()
                let exportFolder = existing.notesLink?.exportFolderID
                next.prompts[i].notesLink = NotesLink(accountID: content.accountID, noteID: content.noteID, remoteRevision: content.revision, localFingerprint: fingerprint(next.prompts[i]), exportFolderID: exportFolder == content.folderID ? exportFolder : nil)
                report.updated += 1
            } else {
                var prompt = Prompt(title: cleanTitle, body: content.promptBody, categoryID: categoryID, markdown: content.documents.first)
                prompt.additionalMarkdown = content.documents.count > 1 ? Array(content.documents.dropFirst()) : nil
                prompt.syncMarkdownBody = false
                prompt.notesLink = NotesLink(accountID: content.accountID, noteID: content.noteID, remoteRevision: content.revision, localFingerprint: fingerprint(prompt))
                next.prompts.insert(prompt, at: 0); report.added += 1
            }
        }
        try next.validate(); _ = try LibraryFile.encode(next)
        library = next; return report
    }
}
