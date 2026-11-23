import AppKit
import Combine
import PromptCore
import UniformTypeIdentifiers

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var library: PromptLibrary
    @Published var filter: LibraryFilter = .all { didSet { refreshResults() } }
    @Published var query = "" { didSet { refreshResults() } }
    @Published var selectedID: UUID?
    @Published var page: AppPage = .library
    @Published var errorMessage: String?
    @Published var toast: String?
    @Published var editor: PromptDraft?
    @Published var accessibilityAllowed = AXIsProcessTrusted()
    @Published var pendingImport: PromptLibrary?
    var openPanel: (() -> Void)?
    var updateHotkey: ((Hotkey) -> Bool)?
    var recordingHotkey: ((Bool) -> Void)?
    @Published private(set) var isLoading = true
    @Published private(set) var isImporting = false
    @Published private(set) var isSaving = false
    @Published private(set) var revision = 0
    @Published private(set) var resultsRevision = 0
    @Published private(set) var visiblePrompts: [Prompt] = []
    private var searchTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var disk: LibraryDisk!
    private var undoLibrary: PromptLibrary?
    private var toastTask: Task<Void, Never>?
    private let file: LibraryFile
    private let demoAttachmentDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("PromptShelf-Demo-\(UUID().uuidString)")
    lazy var notesSync = NotesSyncModel()
    let isDemo: Bool

    init(demo: Bool = false, storageURL: URL? = nil) {
        isDemo = demo
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PromptShelf", isDirectory: true)
        file = LibraryFile(url: storageURL ?? directory.appendingPathComponent("library.json"))
        library = demo ? .seed : PromptLibrary(categories: [.init(id: PromptCategory.generalID, name: "通用")], prompts: [])
        disk = LibraryDisk(file: file)
        if demo { isLoading = false; refreshResults(); selectedID = visiblePrompts.first?.id }
        else {
            Task { [weak self] in
                guard let self else { return }
                defer { self.isLoading = false }
                do {
                    let (loaded, recovered) = try await self.disk.load()
                    self.library = loaded; self.revision += 1; self.refreshResults()
                    self.selectedID = self.visiblePrompts.first?.id
                    if self.updateHotkey?(loaded.preferences.hotkey) == false { self.errorMessage = "已载入资料库，但快捷键无法注册。请在设置中更换组合键。" }
                    if recovered { self.notify("已从本地备份恢复资料库") }
                } catch {
                    self.readOnlyRecovery = true
                    self.errorMessage = "资料库无法读取，已暂停写入。原文件和备份均保留在本地，请在数据设置中打开资料库目录进行检查。\n\n\(error.localizedDescription)"
                }
            }
        }
    }

    private func refreshResults() {
        searchTask?.cancel()
        let snapshot = library, filter = filter, query = query
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            visiblePrompts = snapshot.filtered(filter); resultsRevision += 1
        } else {
            searchTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                let results = await Task.detached(priority: .userInitiated) { snapshot.filtered(filter, query: query) }.value
                guard !Task.isCancelled, let self else { return }
                self.visiblePrompts = results; self.resultsRevision += 1
            }
        }
    }
    private func scheduleSave() {
        guard !isDemo else { return }
        saveTask?.cancel(); isSaving = true
        let snapshot = library, currentRevision = revision
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            guard let self else { return }
            do {
                try await self.disk.save(snapshot, revision: currentRevision)
                if self.revision == currentRevision { self.isSaving = false }
            } catch {
                self.errorMessage = "保存失败，当前修改仍保留在内存中。请检查磁盘空间，重试保存或导出备份。\n\n\(error.localizedDescription)"
            }
        }
    }
    func flush() async throws {
        guard !isDemo, !isLoading, !readOnlyRecovery else { return }
        saveTask?.cancel()
        let currentRevision = revision
        try await disk.save(library, revision: currentRevision)
        if revision == currentRevision { isSaving = false }
    }

    private var readOnlyRecovery = false
    var isClosing = false
    var isReadOnly: Bool { readOnlyRecovery || isLoading }
    var storageStatus: String { isLoading ? "正在载入资料库" : readOnlyRecovery ? "资料库只读，原文件已保留" : isSaving ? "有待保存的修改" : "所有修改已保存" }
    var preferences: Preferences { library.preferences }
    var selectedPrompt: Prompt? { library.prompts.first { $0.id == selectedID } }
    var canUndo: Bool { undoLibrary != nil }
    var accent: ColorToken { ColorToken(rawValue: preferences.accent) ?? .blue }
    var pageTitle: String {
        switch filter {
        case .all: return "全部提示词"
        case .favorites: return "我的收藏"
        case .recent: return "最近使用"
        case .category(let id): return library.categories.first { $0.id == id }?.name ?? "提示词"
        }
    }
    var appearance: NSAppearance? {
        switch preferences.appearance {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    @discardableResult
    func commit(_ edit: (inout PromptLibrary) throws -> Void) -> Bool {
        guard !isClosing else { return false }
        guard !isLoading else { errorMessage = "资料库正在载入，请稍候。"; return false }
        guard !readOnlyRecovery else {
            errorMessage = "原资料库无法读取，已暂停写入。请在「数据与备份」中查看资料库目录和备份文件。"
            return false
        }
        do {
            var next = library
            try edit(&next)
            try next.validate(checkContent: false)
            library = next; revision += 1; refreshResults(); scheduleSave()
            if let selectedID, !next.prompts.contains(where: { $0.id == selectedID }) {
                self.selectedID = visiblePrompts.first?.id
            }
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func selectFilter(_ newFilter: LibraryFilter) {
        filter = newFilter; page = .library; query = ""
        selectedID = visiblePrompts.first?.id
    }
    func newPrompt() {
        let category: UUID
        if case .category(let id) = filter { category = id } else { category = PromptCategory.generalID }
        editor = PromptDraft(prompt: Prompt(title: "", body: "", categoryID: category), isNew: true)
    }
    func edit(_ prompt: Prompt) { editor = PromptDraft(prompt: prompt, isNew: false) }
    func save(_ draft: PromptDraft) -> Bool {
        var prompt = draft.prompt
        prompt.title = prompt.title.trimmingCharacters(in: .whitespacesAndNewlines)
        do { try prompt.validateContent() } catch { errorMessage = error.localizedDescription; return false }
        prompt.updatedAt = Date()
        let success = commit { library in
            if prompt.syncMarkdownBody != false, let document = prompt.markdown, try document.text != prompt.body {
                try prompt.markdown?.updateBody(prompt.body)
            }
            if let i = library.prompts.firstIndex(where: { $0.id == prompt.id }) { library.prompts[i] = prompt }
            else { library.prompts.insert(prompt, at: 0) }
        }
        if success {
            editor = nil; query = ""; filter = .category(prompt.categoryID); page = .library
            selectedID = prompt.id; notify(draft.isNew ? "提示词已添加" : "修改已更新")
        }
        return success
    }
    func toggleFavorite(_ prompt: Prompt) {
        commit { library in
            guard let i = library.prompts.firstIndex(where: { $0.id == prompt.id }) else { return }
            library.prompts[i].isFavorite.toggle()
        }
    }
    func duplicate(_ prompt: Prompt) {
        var copy = prompt; copy.id = UUID(); copy.title = String(prompt.title.prefix(116)) + " 副本"
        copy.createdAt = Date(); copy.updatedAt = Date(); copy.lastUsedAt = nil; copy.useCount = 0; copy.notesLink = nil
        editor = PromptDraft(prompt: copy, isNew: true)
    }
    func delete(_ prompt: Prompt) {
        let previous = library
        if commit({ $0.prompts.removeAll { $0.id == prompt.id } }) {
            undoLibrary = previous; notify("已删除「\(prompt.title)」", preservesUndo: true)
        }
    }
    func undo() {
        guard let old = undoLibrary else { return }
        // Restore deleted records only, preserving newer edits, favorites and preferences.
        if commit({ current in
            for category in old.categories where !current.categories.contains(where: { $0.id == category.id }) {
                current.categories.append(category)
            }
            for prompt in old.prompts where !current.prompts.contains(where: { $0.id == prompt.id }) {
                current.prompts.append(prompt)
            }
        }) { undoLibrary = nil; notify("已撤销删除") }
    }
    func saveCategory(id: UUID?, name: String, symbol: String, color: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 40 else { errorMessage = "分类名称需要 1–40 个字符。"; return false }
        guard !library.categories.contains(where: { $0.id != id && PromptLibrary.normalized($0.name) == PromptLibrary.normalized(clean) }) else {
            errorMessage = "已存在同名分类。"; return false
        }
        let newID = id ?? UUID()
        let result = commit { library in
            if let i = library.categories.firstIndex(where: { $0.id == newID }) {
                library.categories[i].name = clean; library.categories[i].symbol = symbol; library.categories[i].color = color
            } else { library.categories.append(PromptCategory(id: newID, name: clean, symbol: symbol, color: color)) }
        }
        if result { selectFilter(.category(newID)); notify(id == nil ? "分类已创建" : "分类已更新") }
        return result
    }
    func deleteCategory(_ category: PromptCategory) {
        if commit({ $0.removeCategory(category.id) }) {
            selectFilter(.category(PromptCategory.generalID)); notify("分类已删除，提示词已移至通用")
        }
    }
    func copy(_ prompt: Prompt) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt.body, forType: .string)
        markUsed(prompt.id); notify("已复制，可粘贴到任意输入框")
    }
    func markUsed(_ id: UUID) { commit { $0.markUsed(id) } }
    func changePreferences(_ change: (inout Preferences) -> Void) { commit { change(&$0.preferences) } }
    func setHotkey(_ hotkey: Hotkey) {
        guard hotkey.isValid else {
            errorMessage = "这组按键用于常见的系统或编辑操作。请加入 Control、Option 或 Shift，选择其他组合。"; return
        }
        let old = preferences.hotkey
        guard updateHotkey?(hotkey) == true else {
            errorMessage = "这组快捷键无法注册，可能已被其他应用占用。原快捷键保持有效。"; return
        }
        if !commit({ $0.preferences.hotkey = hotkey }) { _ = updateHotkey?(old) }
        else { notify("快捷键已更新为 \(hotkey.display)") }
    }
    func notify(_ text: String, preservesUndo: Bool = false) {
        toastTask?.cancel()
        if !preservesUndo { undoLibrary = nil }
        toast = text
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(preservesUndo ? 8 : 3))
            guard !Task.isCancelled else { return }
            self?.toast = nil
            // Keep the deleted records available for the Edit > Undo command.
        }
    }
    func refreshAccessibility() { accessibilityAllowed = AXIsProcessTrusted() }
    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        accessibilityAllowed = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if !accessibilityAllowed {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
    func exportLibrary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "PromptShelf-提示词库.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let snapshot = library
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { try LibraryFile.encode(snapshot).write(to: url, options: .atomic) }.value
                notify("提示词库已导出")
            } catch { errorMessage = "导出失败：\(error.localizedDescription)" }
        }
    }

    func importLibrary() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do { pendingImport = try await Task.detached(priority: .userInitiated) { try LibraryFile.decode(Data(contentsOf: url)) }.value }
            catch { errorMessage = "导入失败，现有内容未更改。\n\n\(error.localizedDescription)" }
        }
    }
    func confirmImport() {
        guard let incoming = pendingImport else { return }
        var count = 0
        if commit({ count = try $0.merge(incoming) }) { notify("已导入 \(count) 条新提示词"); selectFilter(.all) }
        pendingImport = nil
    }
    func revealLibrary() { NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: "") }

    func readMarkdown(_ url: URL) throws -> MarkdownDocument {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try MarkdownDocument.read(url)
    }
    func chooseMarkdownFiles() {
        let panel = NSOpenPanel()
        panel.title = "导入 Markdown"; panel.prompt = "导入"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText]
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK { importMarkdown(panel.urls) }
    }
    func importMarkdown(_ urls: [URL]) {
        guard !urls.isEmpty, !isImporting, !isLoading else { return }
        guard urls.count <= 200 else { errorMessage = "单次最多导入 200 个 Markdown 文件。"; return }
        let category: UUID
        if case .category(let id) = filter { category = id } else { category = PromptCategory.generalID }
        isImporting = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isImporting = false }
            do {
                let imports = try await Task.detached(priority: .userInitiated) {
                    var total = 0
                    return try urls.map { url -> Prompt in
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let document = try MarkdownDocument.read(url)
                        total += document.data.count
                        guard total <= 256_000_000 else { throw LibraryError.invalid("单次导入总量不能超过 256 MB。") }
                        return Prompt(title: document.title, body: try document.text, categoryID: category, markdown: document)
                    }
                }.value
                var inserted: [Prompt] = []
                if self.commit({ library in
                    // Keep the destination valid if its category was removed during the import.
                    let destination = library.categories.contains { $0.id == category } ? category : PromptCategory.generalID
                    for var prompt in imports {
                        prompt.categoryID = destination
                        if !library.prompts.contains(where: { $0.categoryID == destination && $0.markdown == prompt.markdown && $0.body == prompt.body }) && !inserted.contains(where: { $0.markdown == prompt.markdown && $0.body == prompt.body }) { inserted.append(prompt) }
                    }
                    library.prompts.insert(contentsOf: inserted, at: 0)
                }) {
                    self.selectFilter(.all); self.selectedID = inserted.first?.id ?? self.visiblePrompts.first?.id
                    try await self.flush()
                    self.notify(inserted.isEmpty ? "文件已存在，未重复导入" : "已导入 \(inserted.count) 个 Markdown 文件")
                }
            } catch { self.errorMessage = "导入未完成：\(error.localizedDescription)" }
        }
    }
    func acceptMarkdownDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        Task {
            do {
                var urls: [URL] = []
                for provider in providers {
                    let url: URL = try await withCheckedThrowingContinuation { continuation in
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, error in
                            if let error { continuation.resume(throwing: error) }
                            else if let url = value as? URL { continuation.resume(returning: url) }
                            else if let data = value as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { continuation.resume(returning: url) }
                            else { continuation.resume(throwing: LibraryError.invalid("无法读取拖入的文件。")) }
                        }
                    }
                    urls.append(url)
                }
                importMarkdown(urls)
            } catch { errorMessage = error.localizedDescription }
        }
        return true
    }
    func markdownURL(for prompt: Prompt, document requested: MarkdownDocument? = nil) throws -> URL {
        guard let document = requested ?? prompt.markdown else { throw LibraryError.invalid("此提示词未关联 Markdown 文件。") }
        if !isDemo { return try file.markdownURL(for: prompt, document: document) }
        let index = prompt.markdownDocuments.firstIndex(of: document) ?? 0
        return try document.materialize(in: demoAttachmentDirectory.appendingPathComponent("attachment-\(index)"), promptID: prompt.id)
    }

    func markdownURLs(for prompt: Prompt) throws -> [URL] {
        try prompt.markdownDocuments.map { try markdownURL(for: prompt, document: $0) }
    }
    func fileProvider(for prompt: Prompt, document: MarkdownDocument? = nil) -> NSItemProvider {
        do { return NSItemProvider(object: try markdownURL(for: prompt, document: document) as NSURL) }
        catch { errorMessage = "文件读取失败：\(error.localizedDescription)"; return NSItemProvider() }
    }
    func revealMarkdown(_ prompt: Prompt, document: MarkdownDocument? = nil) {
        do { NSWorkspace.shared.activateFileViewerSelecting([try markdownURL(for: prompt, document: document)]) }
        catch { errorMessage = error.localizedDescription }
    }
}

enum AppPage { case library, appearance, behavior, data, notes, about }
struct PromptDraft: Identifiable {
    var id: UUID { prompt.id }
    var prompt: Prompt
    var isNew: Bool
}
