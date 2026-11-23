import Foundation
import PromptCore

struct NotesBridgeError: LocalizedError, Decodable {
    var code: Int
    var message: String
    var errorDescription: String? {
        if code == -1743 || message.contains("-1743") { return "未允许访问备忘录。请在系统设置 → 隐私与安全性 → 自动化中，允许词屿控制备忘录后重试。" }
        return message
    }
}
private struct NotesEnvelope<T: Decodable>: Decodable { var ok: Bool; var result: T?; var error: NotesBridgeError? }
struct NotesPage: Decodable { var total: Int; var entries: [NotesEntry] }
struct NotesExportReceipt: Decodable { var noteID: String; var revision: String; var folderID: String }
private struct NotesReadReceipt: Decodable {
    struct File: Decodable { var name: String; var path: String }
    var id: String; var title: String; var plainText: String; var revision: String; var files: [File]; var folderID: String
}
actor NotesService {
    private func invoke<T: Decodable>(_ action: String, values: [String: Any] = [:], in directory: URL? = nil) async throws -> T {
        guard let script = Bundle.main.url(forResource: "NotesBridge", withExtension: "js") else { throw LibraryError.invalid("备忘录同步组件缺失，请重新安装词屿。") }
        let folder = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("PromptShelf-Notes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { if directory == nil { try? FileManager.default.removeItem(at: folder) } }
        var request = values; request["action"] = action
        let input = folder.appendingPathComponent("request.json"), output = folder.appendingPathComponent("response.json"), errorURL = folder.appendingPathComponent("stderr.txt")
        try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys]).write(to: input, options: .atomic)
        FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let stdout = try FileHandle(forWritingTo: output), stderr = try FileHandle(forWritingTo: errorURL)
        defer { try? stdout.close(); try? stderr.close() }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", script.path, input.path]
        process.standardOutput = stdout; process.standardError = stderr
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { task in continuation.resume(returning: task.terminationStatus) }
            do { try process.run(); DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: timeout) }
            catch { process.terminationHandler = nil; continuation.resume(throwing: error) }
        }
        timeout.cancel()
        guard status == 0 else { throw LibraryError.invalid("备忘录连接失败或操作超时。请确认系统授权、账户与附件下载状态后重试。") }
        let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 30_000_000 else { throw LibraryError.invalid("备忘录内容超过同步上限。") }
        let envelope = try JSONDecoder().decode(NotesEnvelope<T>.self, from: Data(contentsOf: output))
        guard envelope.ok, let result = envelope.result else { throw envelope.error ?? NotesBridgeError(code: 1000, message: "备忘录同步失败。") }
        return result
    }
    func accounts() async throws -> [NotesAccount] { try await invoke("accounts") }
    func folders(accountID: String) async throws -> [NotesFolder] { try await invoke("folders", values: ["accountID": accountID]) }
    func list(accountID: String, folderID: String, offset: Int) async throws -> NotesPage {
        try await invoke("list", values: ["accountID":accountID,"folderID":folderID,"offset":offset,"limit":100])
    }
    func read(accountID: String, noteID: String, folderID: String) async throws -> NotesContent {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PromptShelf-Notes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let receipt: NotesReadReceipt = try await invoke("read", values: ["accountID":accountID,"noteID":noteID,"folderID":folderID,"directory":directory.path], in: directory)
        let documents = try receipt.files.enumerated().map { index, file -> MarkdownDocument in
            let expected = directory.appendingPathComponent("\(index).md")
            guard URL(fileURLWithPath: file.path).standardizedFileURL == expected.standardizedFileURL else { throw LibraryError.invalid("备忘录附件路径无效。") }
            let imported = try MarkdownDocument.read(expected)
            return try MarkdownDocument(fileName: file.name, data: imported.data)
        }
        return NotesContent(accountID: accountID, noteID: receipt.id, title: receipt.title, plainText: receipt.plainText, revision: receipt.revision, documents: documents, folderID: receipt.folderID)
    }
    func revision(accountID: String, noteID: String, folderID: String?) async throws -> String {
        var values = ["accountID":accountID,"noteID":noteID]
        if let folderID { values["folderID"] = folderID }
        return try await invoke("revision", values: values)
    }
    func export(_ prompt: Prompt, accountID: String) async throws -> NotesExportReceipt {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PromptShelf-Notes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try prompt.markdownDocuments.map { document -> [String:String] in
            let url = try document.materialize(in: directory.appendingPathComponent("files"), promptID: UUID())
            return ["name":document.fileName,"path":url.path]
        }
        return try await invoke("export", values: ["accountID":accountID,"title":prompt.title,"html":NotesSync.html(title:prompt.title,body:prompt.body),"files":files,"operationID":UUID().uuidString], in: directory)
    }
}
