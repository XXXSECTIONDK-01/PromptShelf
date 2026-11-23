import Foundation
import PromptCore

final class LibraryTests {
    func testInterfaceScaleDefaultsForOldLibrariesAndKeepsPreferences() throws {
        var original = PromptLibrary.seed
        original.preferences.hotkey = Hotkey(keyCode: 49, modifiers: 6144)
        original.preferences.fontSize = 17
        var root = try JSONSerialization.jsonObject(with: LibraryFile.encode(original)) as! [String: Any]
        var prefs = root["preferences"] as! [String: Any]
        prefs.removeValue(forKey: "uiScale"); root["preferences"] = prefs
        let migrated = try LibraryFile.decode(JSONSerialization.data(withJSONObject: root))
        checkEqual(migrated.preferences.uiScale, 1.2)
        checkEqual(migrated, original)
    }
    func testInterfaceScalePersistsAndRejectsInvalidValuesWithoutChangingDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = LibraryFile(url: directory.appendingPathComponent("library.json"))
        var library = PromptLibrary.seed; library.preferences.uiScale = 1.4
        try file.save(library)
        checkEqual(try LibraryFile(url: file.url).load(), library)
        checkEqual(try LibraryFile.decode(LibraryFile.encode(library)), library)
        for scale in [0.79, 1.51, Double.nan, Double.infinity] {
            var invalid = library; invalid.preferences.uiScale = scale
            checkThrows(try file.save(invalid))
        }
        checkEqual(try LibraryFile(url: file.url).load(), library)
    }
    func testInstantDraftDoesNotMutateLibraryOrAttachments() throws {
        var library = PromptLibrary.seed
        library.prompts[0].markdown = try MarkdownDocument(fileName: "original.md", data: Data("原附件".utf8))
        let before = library
        var draft = InstantDraft(prompt: library.prompts[0])
        draft.body = "  本次填写\n\n保留换行和空白  "
        checkEqual(try draft.validatedBody(), "  本次填写\n\n保留换行和空白  ")
        checkEqual(draft.sourceID, library.prompts[0].id)
        checkEqual(library, before)
        draft.body = "\n \t"
        checkThrows(try draft.validatedBody())
        draft.body = String(repeating: "a", count: 20_000_001)
        checkThrows(try draft.validatedBody())
    }
    func testInstantMarkdownKeepsPlainTextAndSafeFileName() throws {
        let prompt = Prompt(title: "../含有/路径\\与:符号.md", body: "# 原始正文\n\n```swift\nlet n = 1\n```\n")
        let document = try InstantOutput.markdownDocuments(for: prompt)[0]
        checkEqual(try document.text, prompt.body)
        checkEqual(document.data, Data(prompt.body.utf8))
        checkTrue(!document.fileName.hasPrefix("."))
        checkTrue(!document.fileName.contains("/"))
        checkTrue(!document.fileName.contains("\\"))
        checkTrue(!document.fileName.contains(":"))
        checkTrue(!document.fileName.hasSuffix(".md.md"))
        let long = try InstantOutput.markdownDocuments(for: Prompt(title: String(repeating: "长", count: 120), body: "正文"))[0]
        checkTrue(long.fileName.utf8.count <= 184)
    }
    func testInstantMarkdownPreservesAllIndependentAttachments() throws {
        let first = try MarkdownDocument(fileName: "same.md", data: Data("第一份".utf8))
        let second = try MarkdownDocument(fileName: "same.md", data: Data("第二份".utf8))
        var prompt = Prompt(title: "标题", body: "独立笔记正文", markdown: first)
        prompt.additionalMarkdown = [second]
        checkEqual(try InstantOutput.markdownDocuments(for: prompt), [first,second])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try InstantOutput.materialize([first,second], in: root)
        checkTrue(files[0] != files[1])
        checkEqual(try Data(contentsOf: files[0]), first.data)
        checkEqual(try Data(contentsOf: files[1]), second.data)
    }
    func testInstantFileLifetimeAndExpiredSessionCleanup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try MarkdownDocument(fileName: "one.md", data: Data("一".utf8))
        let second = try MarkdownDocument(fileName: "two.md", data: Data("二".utf8))
        let old = try InstantOutput.materialize([first], in: root)
        let current = try InstantOutput.materialize([second], in: root)
        checkEqual(try Data(contentsOf: old[0]), first.data)
        checkEqual(try Data(contentsOf: current[0]), second.data)
        let unrelated = root.appendingPathComponent("keep-me")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        _ = try InstantOutput.materialize([first], in: root, now: Date().addingTimeInterval(90_000))
        checkTrue(!FileManager.default.fileExists(atPath: old[0].path))
        checkTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }
    func testSeedIsValidAndHasRequiredCategories() throws {
        let library = PromptLibrary.seed
        try library.validate()
        checkEqual(library.prompts.count, 9)
        checkNotNil(library.categories.first { $0.id == PromptCategory.generalID })
    }
    func testSearchMatchesContentAndCategoryWithAllTerms() {
        let library = PromptLibrary.seed
        checkEqual(library.filtered(.all, query: "ａｉｇｃ 图像").map(\.title), ["高质量图像提示词"])
        checkTrue(library.filtered(.all, query: "虚构 JSON").contains { $0.title == "生成结构化测试数据" })
        checkTrue(library.filtered(.all, query: "虚构 不存在的词").isEmpty)
    }
    func testFiltersAndRecencyUseActualUsage() {
        var library = PromptLibrary.seed
        checkTrue(library.filtered(.recent).isEmpty)
        let first = library.prompts[0].id, second = library.prompts[2].id
        library.markUsed(first, at: Date(timeIntervalSince1970: 100))
        library.markUsed(second, at: Date(timeIntervalSince1970: 200))
        checkEqual(library.filtered(.recent).map(\.id), [second, first])
        checkEqual(library.prompts.first { $0.id == first }?.useCount, 1)
        checkTrue(library.filtered(.favorites).allSatisfy(\.isFavorite))
    }
    func testDeletingCategoryKeepsAllPrompts() throws {
        var library = PromptLibrary.seed
        let categoryID = library.categories[1].id
        let affected = library.prompts.filter { $0.categoryID == categoryID }.map(\.id)
        library.removeCategory(categoryID)
        checkEqual(library.prompts.count, 9)
        checkTrue(library.prompts.filter { affected.contains($0.id) }.allSatisfy { $0.categoryID == PromptCategory.generalID })
        try library.validate()
    }
    func testGeneralCategoryCannotBeDeleted() {
        var library = PromptLibrary.seed
        library.removeCategory(PromptCategory.generalID)
        checkNotNil(library.categories.first { $0.id == PromptCategory.generalID })
    }
    func testImportIsIdempotentAndKeepsLocalPreferences() throws {
        var local = PromptLibrary.seed
        local.preferences.accent = "rose"
        checkEqual(try local.merge(.seed), 0)
        checkEqual(try local.merge(.seed), 0)
        checkEqual(local.prompts.count, 9)
        checkEqual(local.preferences.accent, "rose")
    }
    func testIDCollisionCreatesCopyInsteadOfOverwriting() throws {
        var local = PromptLibrary.seed
        var incoming = PromptLibrary.seed
        incoming.prompts[0].body = "来自另一台设备的新版本。"
        let original = local.prompts[0]
        checkEqual(try local.merge(incoming), 1)
        checkEqual(local.prompts.first { $0.id == original.id }, original)
        checkEqual(local.prompts.count, 10)
        checkEqual(Set(local.prompts.map(\.id)).count, 10)
    }
    func testImportMapsMatchingCategoryNames() throws {
        var local = PromptLibrary.seed
        var incoming = PromptLibrary.seed
        let oldID = incoming.categories[1].id, newID = UUID()
        incoming.categories[1].id = newID
        for i in incoming.prompts.indices where incoming.prompts[i].categoryID == oldID { incoming.prompts[i].categoryID = newID }
        checkEqual(try local.merge(incoming), 0)
        checkEqual(local.categories.count, 4)
    }
    func testInvalidImportDoesNotPartiallyMutateLibrary() throws {
        var local = PromptLibrary.seed
        let before = local
        var invalid = PromptLibrary.seed
        invalid.categories.append(PromptCategory(name: "新的分类"))
        invalid.prompts[0].categoryID = UUID()
        checkThrows(try local.merge(invalid))
        checkEqual(local, before)
    }
    func testDuplicateNamesAndInvalidPreferencesRejected() {
        var library = PromptLibrary.seed
        library.categories.append(PromptCategory(name: "ａｉｇｃ"))
        checkThrows(try library.validate())
        library = .seed; library.preferences.panelWidth = 10
        checkThrows(try library.validate())
        library = .seed; library.preferences.hotkey.modifiers = 0
        checkThrows(try library.validate())
        library = .seed; library.preferences.hotkey = Hotkey(keyCode: 12, modifiers: 256)
        checkThrows(try library.validate())
        checkTrue(!Hotkey().isReserved)
    }
    func testLegacyAppearanceMigrationPreservesCustomSettings() throws {
        let legacy = "{\"theme\":\"liquidGlass\",\"appearance\":\"dark\",\"accent\":\"rose\",\"fontSize\":13,\"panelWidth\":540,\"hotkey\":{\"keyCode\":40,\"modifiers\":6400}}"
        let migrated = try JSONDecoder().decode(Preferences.self, from: Data(legacy.utf8))
        checkEqual(migrated.fontSize, 15)
        checkEqual(migrated.panelWidth, 500)
        checkEqual(migrated.theme, .liquidGlass)
        checkEqual(migrated.accent, "rose")
        checkEqual(migrated.hotkey, Hotkey(keyCode: 40, modifiers: 6400))
        let custom = legacy.replacingOccurrences(of: "\"fontSize\":13", with: "\"fontSize\":17").replacingOccurrences(of: "\"panelWidth\":540", with: "\"panelWidth\":620")
        let preserved = try JSONDecoder().decode(Preferences.self, from: Data(custom.utf8))
        checkEqual(preserved.fontSize, 17)
        checkEqual(preserved.panelWidth, 620)
        var explicitlySmall = Preferences(); explicitlySmall.fontSize = 13
        checkEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(explicitlySmall)), explicitlySmall)
    }
    func testShortcutValidationAllowsNavigationAndFunctionKeys() {
        for code: UInt32 in [0, 18, 35, 40, 42, 49, 96, 122, 123, 126] {
            checkTrue(Hotkey(keyCode: code, modifiers: 6144).isValid)
        }
        checkTrue(!Hotkey(keyCode: 56, modifiers: 6144).isValid)
        checkTrue(!Hotkey(keyCode: 53, modifiers: 6144).isValid)
        checkTrue(!Hotkey(keyCode: 35, modifiers: 512).isValid)
        checkTrue(!Hotkey(keyCode: 8, modifiers: 256).isValid)
        checkTrue(!Hotkey(keyCode: 35, modifiers: 65536).isValid)
    }
    func testMarkdownOwnsCopyAfterOriginalIsRemoved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("测试提示词.md")
        let body = "# 工作指令\n\n保留 **加粗**、列表与代码。\n- 一\n```json\n{\"ok\":true}\n```\n"
        let original = Data(body.utf8); try original.write(to: source)
        let document = try MarkdownDocument.read(source)
        checkEqual(document.title, "测试提示词")
        checkEqual(try document.text, body)
        try FileManager.default.removeItem(at: source)
        var library = PromptLibrary.seed
        let prompt = Prompt(title: document.title, body: body, markdown: document)
        library.prompts.append(prompt)
        let restored = try LibraryFile.decode(LibraryFile.encode(library))
        let attachment = restored.prompts.last!.markdown!
        let copied = try attachment.materialize(in: folder.appendingPathComponent("owned"), promptID: prompt.id)
        checkEqual(try Data(contentsOf: copied), original)
        checkTrue(!FileManager.default.fileExists(atPath: source.path))
    }
    func testMarkdownSameNamesAndBodyUpdatesStayIndependent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var first = try MarkdownDocument(fileName: "prompt.md", data: Data("第一份".utf8))
        let second = try MarkdownDocument(fileName: "prompt.md", data: Data("第二份".utf8))
        let a = UUID(), b = UUID()
        let aURL = try first.materialize(in: folder, promptID: a)
        let bURL = try second.materialize(in: folder, promptID: b)
        checkTrue(aURL != bURL)
        try first.updateBody("更新后的正文")
        _ = try first.materialize(in: folder, promptID: a)
        checkEqual(try String(contentsOf: aURL, encoding: .utf8), "更新后的正文")
        checkEqual(try String(contentsOf: bURL, encoding: .utf8), "第二份")
        let old = first
        checkThrows(try first.updateBody(""))
        checkEqual(first, old)
    }
    func testMarkdownEncodingAndInvalidFiles() throws {
        let utf8 = Data([0xEF,0xBB,0xBF]) + Data("正文".utf8)
        checkEqual(try MarkdownDocument(fileName: "bom.MD", data: utf8).text, "正文")
        let utf16 = "UTF16 正文".data(using: .utf16)!
        checkEqual(try MarkdownDocument(fileName: "wide.markdown", data: utf16).text, "UTF16 正文")
        for name in ["../prompt.md", "a/b.md", "a\\b.md", "prompt.txt", "a:b.md", "\nprompt.md"] {
            checkThrows(try MarkdownDocument(fileName: name, data: Data("text".utf8)))
        }
        checkThrows(try MarkdownDocument(fileName: "empty.md", data: Data(" \n ".utf8)))
        checkThrows(try MarkdownDocument(fileName: "binary.md", data: Data([0x00,0xFF,0x80])))
        checkThrows(try MarkdownDocument(fileName: "large.md", data: Data(repeating: 65, count: 20_000_001)))
    }
    func testMarkdownMergeKeepsAttachmentAndDeduplicates() throws {
        var local = PromptLibrary.seed
        let base = local.prompts[0]
        var incoming = PromptLibrary.seed
        incoming.prompts[0].markdown = try MarkdownDocument(fileName: "prompt.md", data: Data(base.body.utf8))
        checkEqual(try local.merge(incoming), 1)
        checkEqual(try local.merge(incoming), 0)
        checkEqual(local.prompts.filter { $0.markdown != nil }.count, 1)
        checkTrue(local.prompts.contains { $0.id == base.id && $0.markdown == nil })
    }
    func testLegacyLibraryWithoutMarkdownMigrates() throws {
        var old = PromptLibrary.seed; old.version = 1
        let data = try LibraryFile.encode(old)
        let restored = try LibraryFile.decode(data)
        checkEqual(restored.version, 3)
        checkEqual(restored.prompts, old.prompts)
        checkTrue(restored.prompts.allSatisfy { $0.markdown == nil })
    }
    func testNotesImportIncludesAllMarkdownAndIsIdempotent() throws {
        var library = PromptLibrary.seed
        let first = try MarkdownDocument(fileName: "first.md", data: Data("第一份附件".utf8))
        let second = try MarkdownDocument(fileName: "second.md", data: Data("第二份附件".utf8))
        let note = NotesContent(accountID: "account", noteID: "note", title: "笔记", plainText: "笔记\n\n独立正文\n\u{fffc}", revision: "v1", documents: [first,second])
        let report = try NotesSync.importContents([note], categoryID: PromptCategory.generalID, into: &library)
        checkEqual(report.added, 1)
        let prompt = library.prompts.first!
        checkEqual(prompt.body, "独立正文")
        checkEqual(prompt.markdownDocuments, [first,second])
        checkEqual(prompt.syncMarkdownBody, false)
        checkEqual(prompt.notesLink?.localFingerprint, NotesSync.fingerprint(prompt))
        checkEqual(try NotesSync.importContents([note], categoryID: PromptCategory.generalID, into: &library).skipped, 1)
        var restored = try LibraryFile.decode(LibraryFile.encode(library))
        checkEqual(restored.prompts[0].markdownDocuments, prompt.markdownDocuments)
        checkEqual(restored.prompts[0].notesLink?.noteID, prompt.notesLink?.noteID)
        checkEqual(restored.prompts[0].notesLink?.localFingerprint, NotesSync.fingerprint(prompt))
        checkEqual(restored.prompts[0].syncMarkdownBody, false)
        checkEqual(try NotesSync.importContents([note], categoryID: PromptCategory.generalID, into: &restored).skipped, 1)
    }
    func testNotesConflictPreservesLocalCopyBeforePull() throws {
        var library = PromptLibrary.seed
        var note = NotesContent(accountID: "account", noteID: "note", title: "笔记", plainText: "笔记\n远端一", revision: "v1")
        _ = try NotesSync.importContents([note], categoryID: PromptCategory.generalID, into: &library)
        let id = library.prompts[0].id
        library.prompts[0].body = "本地修改"
        note.plainText = "笔记\n远端二"; note.revision = "v2"
        let report = try NotesSync.importContents([note], categoryID: PromptCategory.generalID, into: &library)
        checkEqual(report.updated, 1); checkEqual(report.preserved, 1)
        checkEqual(library.prompts.first { $0.id == id }?.body, "远端二")
        checkTrue(library.prompts.contains { $0.body == "本地修改" && $0.notesLink == nil })
        checkEqual(try NotesSync.importContents([note], categoryID: PromptCategory.generalID, into: &library).skipped, 1)
    }
    func testNotesUnchangedRemoteDoesNotReplaceLocalEdits() throws {
        var library = PromptLibrary.seed
        let note = NotesContent(accountID: "a", noteID: "n", title: "标题", plainText: "标题\n内容", revision: "1")
        _ = try NotesSync.importContents([note], categoryID: PromptCategory.generalID, into: &library)
        library.prompts[0].body = "尚未导出的本地修改"
        let before = library
        let report = try NotesSync.importContents([note], categoryID: PromptCategory.generalID, into: &library)
        checkEqual(report.skipped, 1); checkEqual(library,before)
    }
    func testNotesBatchFailureKeepsWholeLibrary() throws {
        var library = PromptLibrary.seed
        let before = library
        let valid = NotesContent(accountID: "a", noteID: "n", title: "标题", plainText: "有效", revision: "1")
        var invalid = valid; invalid.noteID = "broken"; invalid.plainText = String(repeating: "a", count: 20_000_001)
        checkThrows(try NotesSync.importContents([valid,invalid], categoryID: PromptCategory.generalID, into: &library))
        checkEqual(library,before)
        checkThrows(try NotesSync.importContents(Array(repeating: valid, count: 21), categoryID: PromptCategory.generalID, into: &library))
        checkEqual(library,before)
    }
    func testNotesHTMLCannotInterpretPromptAsMarkup() {
        let html = NotesSync.html(title: "A < B & C", body: "<script>alert(1)</script>\n\"quoted\"\n\n尾行")
        checkTrue(html.contains("A &lt; B &amp; C"))
        checkTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        checkTrue(!html.contains("<script>"))
        checkTrue(html.contains("&quot;quoted&quot;"))
        checkTrue(html.contains("<pre>")); checkTrue(html.contains("\n\n"))
    }
    func testNotesFingerprintDetectsAttachmentsAndIgnoresUsage() throws {
        var prompt = Prompt(title: "标题", body: "正文")
        let original = NotesSync.fingerprint(prompt)
        prompt.useCount = 9; prompt.isFavorite = true; prompt.updatedAt = Date()
        checkEqual(NotesSync.fingerprint(prompt), original)
        prompt.markdown = try MarkdownDocument(fileName: "a.md", data: Data("附件".utf8))
        let primary = NotesSync.fingerprint(prompt)
        checkTrue(primary != original)
        prompt.additionalMarkdown = [try MarkdownDocument(fileName: "b.md", data: Data("第二份".utf8))]
        checkTrue(NotesSync.fingerprint(prompt) != primary)
    }
    func testNotesExportRequiresManagedDestination() throws {
        var library = PromptLibrary.seed
        var note = NotesContent(accountID: "a", noteID: "n", title: "标题", plainText: "标题\n内容", revision: "1", folderID: "source")
        _ = try NotesSync.importContents([note], categoryID: PromptCategory.generalID, into: &library)
        checkTrue(NotesSync.exportBaseline(library.prompts[0], accountID: "a") == nil)
        library.prompts[0].notesLink?.exportFolderID = "managed"
        checkTrue(NotesSync.exportBaseline(library.prompts[0], accountID: "a") != nil)
        checkTrue(NotesSync.exportBaseline(library.prompts[0], accountID: "other") == nil)
        let restored = try LibraryFile.decode(LibraryFile.encode(library))
        checkEqual(restored.prompts[0].notesLink?.exportFolderID, "managed")
        library.prompts[0].body = "本地修改"
        checkTrue(NotesSync.exportBaseline(library.prompts[0], accountID: "a") == nil)
        library.prompts[0] = restored.prompts[0]
        note.revision = "2"; note.folderID = "managed"
        _ = try NotesSync.importContents([note], categoryID: PromptCategory.generalID, into: &library)
        checkTrue(NotesSync.exportBaseline(library.prompts[0], accountID: "a") != nil)
        note.revision = "3"; note.folderID = "moved"
        _ = try NotesSync.importContents([note], categoryID: PromptCategory.generalID, into: &library)
        checkTrue(NotesSync.exportBaseline(library.prompts[0], accountID: "a") == nil)
    }
    func testNotesBodyFallbackAndHeadingRemoval() throws {
        let document = try MarkdownDocument(fileName: "only.md", data: Data("# 附件正文".utf8))
        var note = NotesContent(accountID: "a", noteID: "n", title: "标题", plainText: "标题\n\u{fffc}", revision: "1", documents: [document])
        checkEqual(note.promptBody,"# 附件正文")
        note.plainText = "标题\n第一行\n标题\n末行"
        checkEqual(note.promptBody,"第一行\n标题\n末行")
        note.plainText = "正文没有重复标题"
        checkEqual(note.promptBody,"正文没有重复标题")
    }
    func testRoundTripPreservesContentAndMetadata() throws {
        let original = PromptLibrary.seed
        let decoded = try LibraryFile.decode(LibraryFile.encode(original))
        checkEqual(decoded, original)
    }
    func testSavingCreatesRecoverablePreviousVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = LibraryFile(url: directory.appendingPathComponent("library.json"))
        let first = PromptLibrary.seed
        var second = first; second.prompts.removeFirst()
        try file.save(first); try file.save(second)
        checkEqual(try file.load(), second)
        checkEqual(try file.loadBackup(), first)
    }
    func testInvalidSaveKeepsExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = LibraryFile(url: directory.appendingPathComponent("library.json"))
        let first = PromptLibrary.seed
        try file.save(first)
        var invalid = first; invalid.prompts[0].title = "  "
        checkThrows(try file.save(invalid))
        checkEqual(try file.load(), first)
    }
    func testUnsupportedVersionAndOversizedFileAreRejected() throws {
        var future = PromptLibrary.seed; future.version = 4
        checkThrows(try future.validate())
        checkThrows(try LibraryFile.decode(Data(repeating: 32, count: 25_000_001)))
    }
    func testEncodingCannotCreateAnUnreadableOversizedLibrary() {
        var library = PromptLibrary.seed
        library.prompts = [Prompt(title: "Oversized", body: String(repeating: "a", count: 20_000_001))]
        checkThrows(try LibraryFile.encode(library))
    }
    func testCorruptPrimaryDoesNotOverwriteValidBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = LibraryFile(url: directory.appendingPathComponent("library.json"))
        let original = PromptLibrary.seed
        var newer = original; newer.prompts.removeFirst()
        try file.save(original); try file.save(newer)
        try Data("invalid json".utf8).write(to: file.url)
        checkThrows(try file.load())
        checkThrows(try file.save(newer))
        checkEqual(try file.loadBackup(), original)
        try file.save(newer)
        checkEqual(try file.loadBackup(), original)
        checkEqual(try file.load(), newer)
    }
}

private func fail(_ message: String, file: StaticString, line: UInt) -> Never {
    fputs("FAIL \(file):\(line): \(message)\n", stderr)
    exit(1)
}
private func checkTrue(_ expression: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !expression() { fail("Expected true", file: file, line: line) }
}
private func checkEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { if try lhs() != rhs() { fail("Values are not equal", file: file, line: line) } }
    catch { fail(error.localizedDescription, file: file, line: line) }
}
private func checkNotNil<T>(_ expression: @autoclosure () -> T?, file: StaticString = #filePath, line: UInt = #line) {
    if expression() == nil { fail("Expected a value", file: file, line: line) }
}
private func checkThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression() } catch { return }
    fail("Expected validation to fail", file: file, line: line)
}

@main
struct CoreChecks {
    static func main() throws {
        let suite = LibraryTests()
        let cases: [(String, () throws -> Void)] = [
            ("testInterfaceScaleDefaultsForOldLibrariesAndKeepsPreferences", suite.testInterfaceScaleDefaultsForOldLibrariesAndKeepsPreferences),
            ("testInterfaceScalePersistsAndRejectsInvalidValuesWithoutChangingDisk", suite.testInterfaceScalePersistsAndRejectsInvalidValuesWithoutChangingDisk),
            ("testInstantDraftDoesNotMutateLibraryOrAttachments", suite.testInstantDraftDoesNotMutateLibraryOrAttachments),
            ("testInstantMarkdownKeepsPlainTextAndSafeFileName", suite.testInstantMarkdownKeepsPlainTextAndSafeFileName),
            ("testInstantMarkdownPreservesAllIndependentAttachments", suite.testInstantMarkdownPreservesAllIndependentAttachments),
            ("testInstantFileLifetimeAndExpiredSessionCleanup", suite.testInstantFileLifetimeAndExpiredSessionCleanup),
            ("testSeedIsValidAndHasRequiredCategories", suite.testSeedIsValidAndHasRequiredCategories),
            ("testSearchMatchesContentAndCategoryWithAllTerms", suite.testSearchMatchesContentAndCategoryWithAllTerms),
            ("testFiltersAndRecencyUseActualUsage", suite.testFiltersAndRecencyUseActualUsage),
            ("testDeletingCategoryKeepsAllPrompts", suite.testDeletingCategoryKeepsAllPrompts),
            ("testGeneralCategoryCannotBeDeleted", suite.testGeneralCategoryCannotBeDeleted),
            ("testImportIsIdempotentAndKeepsLocalPreferences", suite.testImportIsIdempotentAndKeepsLocalPreferences),
            ("testIDCollisionCreatesCopyInsteadOfOverwriting", suite.testIDCollisionCreatesCopyInsteadOfOverwriting),
            ("testImportMapsMatchingCategoryNames", suite.testImportMapsMatchingCategoryNames),
            ("testInvalidImportDoesNotPartiallyMutateLibrary", suite.testInvalidImportDoesNotPartiallyMutateLibrary),
            ("testDuplicateNamesAndInvalidPreferencesRejected", suite.testDuplicateNamesAndInvalidPreferencesRejected),
            ("testLegacyAppearanceMigrationPreservesCustomSettings", suite.testLegacyAppearanceMigrationPreservesCustomSettings),
            ("testShortcutValidationAllowsNavigationAndFunctionKeys", suite.testShortcutValidationAllowsNavigationAndFunctionKeys),
            ("testMarkdownOwnsCopyAfterOriginalIsRemoved", suite.testMarkdownOwnsCopyAfterOriginalIsRemoved),
            ("testMarkdownSameNamesAndBodyUpdatesStayIndependent", suite.testMarkdownSameNamesAndBodyUpdatesStayIndependent),
            ("testMarkdownEncodingAndInvalidFiles", suite.testMarkdownEncodingAndInvalidFiles),
            ("testMarkdownMergeKeepsAttachmentAndDeduplicates", suite.testMarkdownMergeKeepsAttachmentAndDeduplicates),
            ("testLegacyLibraryWithoutMarkdownMigrates", suite.testLegacyLibraryWithoutMarkdownMigrates),
            ("testNotesImportIncludesAllMarkdownAndIsIdempotent", suite.testNotesImportIncludesAllMarkdownAndIsIdempotent),
            ("testNotesConflictPreservesLocalCopyBeforePull", suite.testNotesConflictPreservesLocalCopyBeforePull),
            ("testNotesUnchangedRemoteDoesNotReplaceLocalEdits", suite.testNotesUnchangedRemoteDoesNotReplaceLocalEdits),
            ("testNotesBatchFailureKeepsWholeLibrary", suite.testNotesBatchFailureKeepsWholeLibrary),
            ("testNotesHTMLCannotInterpretPromptAsMarkup", suite.testNotesHTMLCannotInterpretPromptAsMarkup),
            ("testNotesFingerprintDetectsAttachmentsAndIgnoresUsage", suite.testNotesFingerprintDetectsAttachmentsAndIgnoresUsage),
            ("testNotesExportRequiresManagedDestination", suite.testNotesExportRequiresManagedDestination),
            ("testNotesBodyFallbackAndHeadingRemoval", suite.testNotesBodyFallbackAndHeadingRemoval),
            ("testRoundTripPreservesContentAndMetadata", suite.testRoundTripPreservesContentAndMetadata),
            ("testSavingCreatesRecoverablePreviousVersion", suite.testSavingCreatesRecoverablePreviousVersion),
            ("testInvalidSaveKeepsExistingFile", suite.testInvalidSaveKeepsExistingFile),
            ("testUnsupportedVersionAndOversizedFileAreRejected", suite.testUnsupportedVersionAndOversizedFileAreRejected),
            ("testEncodingCannotCreateAnUnreadableOversizedLibrary", suite.testEncodingCannotCreateAnUnreadableOversizedLibrary),
            ("testCorruptPrimaryDoesNotOverwriteValidBackup", suite.testCorruptPrimaryDoesNotOverwriteValidBackup)
        ]
        for (name, check) in cases {
            try check()
            print("PASS \(name)")
        }
        print("\(cases.count) core checks passed.")
    }
}
