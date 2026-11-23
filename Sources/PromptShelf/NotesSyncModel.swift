import SwiftUI
import PromptCore

@MainActor
final class NotesSyncModel: ObservableObject {
    @Published var accounts: [NotesAccount] = []
    @Published var folders: [NotesFolder] = []
    @Published var entries: [NotesEntry] = []
    @Published var accountID = ""
    @Published var folderID = ""
    @Published var importCategory = PromptCategory.generalID
    @Published var selectedNotes = Set<String>()
    @Published var selectedPrompts = Set<UUID>()
    @Published var query = ""
    @Published var exportQuery = ""
    @Published var busy = false
    @Published var status = "尚未连接备忘录"
    @Published var error: String?
    @Published var summary: String?
    @Published var total = 0
    private let service = NotesService()
    var filteredEntries: [NotesEntry] { entries.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    func connect() {
        perform {
            self.accounts = try await self.service.accounts()
            self.accountID = self.accounts.first(where: { $0.name.lowercased().contains("icloud") })?.id ?? self.accounts.first?.id ?? ""
            guard !self.accountID.isEmpty else { throw LibraryError.invalid("未找到备忘录账户。请先在系统备忘录中启用 iCloud 或本地账户。") }
            try await self.loadFolders(); self.status = "已连接备忘录"
        }
    }
    func changeAccount(_ id: String) {
        accountID = id; folders = []; folderID = ""; entries = []; total = 0; selectedNotes = []
        perform { try await self.loadFolders() }
    }
    private func loadFolders() async throws {
        folders = try await service.folders(accountID: accountID)
        folderID = folders.first(where: { $0.name == "词屿" })?.id ?? folders.first?.id ?? ""
        entries = []; total = 0; selectedNotes = []
        if !folderID.isEmpty { try await loadPage(append: false) }
    }
    func changeFolder(_ id: String) { folderID = id; refresh() }
    func refresh() { selectedNotes = []; perform { try await self.loadPage(append: false) } }
    func loadMore() { perform { try await self.loadPage(append: true) } }
    private func loadPage(append: Bool) async throws {
        guard !folderID.isEmpty else { return }
        let page = try await service.list(accountID: accountID, folderID: folderID, offset: append ? entries.count : 0)
        if append {
            let known = Set(entries.map(\.id)); entries += page.entries.filter { !known.contains($0.id) }
        } else { entries = page.entries }
        total = page.total
    }
    func pull(store: AppStore) {
        let ids = entries.filter { selectedNotes.contains($0.id) && !$0.locked }.map(\.id)
        guard !ids.isEmpty, ids.count <= 20 else { error = "请选择 1–20 条未锁定的备忘录。"; return }
        let account = accountID, category = importCategory, folder = folderID
        perform {
            var contents: [NotesContent] = []
            for (index,id) in ids.enumerated() {
                self.status = "正在读取 \(index + 1) / \(ids.count)"
                contents.append(try await self.service.read(accountID: account, noteID: id, folderID: folder))
            }
            var report = NotesImportReport()
            guard store.commit({ report = try NotesSync.importContents(contents, categoryID: category, into: &$0) }) else {
                throw LibraryError.invalid(store.errorMessage ?? "资料库保存失败，未导入。")
            }
            try await store.flush()
            self.summary = "新增 \(report.added) 条 · 更新 \(report.updated) 条 · 跳过 \(report.skipped) 条" + (report.preserved > 0 ? " · 保留 \(report.preserved) 份本地副本" : "")
            self.status = "导入完成"; self.selectedNotes = []
        }
    }
    func push(store: AppStore) {
        let prompts = store.library.prompts.filter { selectedPrompts.contains($0.id) }
        guard !accountID.isEmpty, !prompts.isEmpty, prompts.count <= 20 else { error = "请选择账户及 1–20 条提示词。"; return }
        let account = accountID
        perform {
            var exported = 0, skipped = 0
            for (index,prompt) in prompts.enumerated() {
                self.status = "正在导出 \(index + 1) / \(prompts.count) · 已保存 \(exported) 条"
                let fingerprint = NotesSync.fingerprint(prompt)
                if let link = NotesSync.exportBaseline(prompt, accountID: account) {
                    do {
                        if try await self.service.revision(accountID: account, noteID: link.noteID, folderID: link.exportFolderID) == link.remoteRevision { skipped += 1; continue }
                    } catch let failure as NotesBridgeError where failure.code == -1728 { /* Recreate a deleted note. */ }
                }
                let receipt = try await self.service.export(prompt, accountID: account)
                let link = NotesLink(accountID: account, noteID: receipt.noteID, remoteRevision: receipt.revision, localFingerprint: fingerprint, exportFolderID: receipt.folderID)
                guard store.commit({ library in
                    if let i = library.prompts.firstIndex(where: { $0.id == prompt.id }) { library.prompts[i].notesLink = link }
                }) else { throw LibraryError.invalid("笔记已保存到备忘录，但本地同步记录保存失败。请检查资料库状态后重试。") }
                try await store.flush()
                exported += 1
                self.summary = "已保存 \(exported) 条 · 跳过 \(skipped) 条"
            }
            self.summary = "已保存 \(exported) 条到「词屿」文件夹 · 跳过 \(skipped) 条未改动内容"
            self.status = "导出完成"; self.selectedPrompts = []
            // Reload folder choices so a newly created destination folder appears immediately.
            self.folders = try await self.service.folders(accountID: account)
        }
    }
    private func perform(_ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true; error = nil; summary = nil
        Task {
            defer { busy = false }
            do { try await work() }
            catch { self.error = error.localizedDescription; status = "同步未完成" }
        }
    }
}
