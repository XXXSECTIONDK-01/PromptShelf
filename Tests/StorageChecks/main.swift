import Foundation
import PromptCore

func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !value() { throw LibraryError.invalid("CHECK FAILED: \(message)") }
}
func elapsed(_ start: Date) -> String { String(format: "%.3f", Date().timeIntervalSince(start)) }
@main struct StorageChecks {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PromptShelf-StorageChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Generate the real early schema, including string preferences and a noncanonical general ID.
        let portable = try LibraryFile.encode(.seed)
        var legacy = try JSONSerialization.jsonObject(with: portable) as! [String: Any]
        var cats = legacy["categories"] as! [[String: Any]], prompts = legacy["prompts"] as! [[String: Any]]
        let oldGeneral = UUID().uuidString
        for i in cats.indices {
            cats[i]["accent"] = cats[i].removeValue(forKey: "color")
            if cats[i]["id"] as? String == PromptCategory.generalID.uuidString { cats[i]["id"] = oldGeneral }
        }
        for i in prompts.indices where prompts[i]["categoryID"] as? String == PromptCategory.generalID.uuidString { prompts[i]["categoryID"] = oldGeneral }
        legacy.removeValue(forKey: "version"); legacy.removeValue(forKey: "preferences")
        legacy["schemaVersion"] = 1; legacy["categories"] = cats; legacy["prompts"] = prompts
        legacy["settings"] = ["theme":"liquidGlass","appearance":"system","accent":"blue","fontSize":"medium","hotkey":"control+option+space","panelWidthPercent":34]
        let legacyBytes = try JSONSerialization.data(withJSONObject: legacy)
        let migrated = try LibraryFile.decode(legacyBytes)
        try require(migrated.prompts == PromptLibrary.seed.prompts, "legacy prompt content, IDs, dates and metadata")
        try require(migrated.preferences.hotkey.keyCode == 49 && migrated.preferences.hotkey.modifiers == 6144, "legacy shortcut")
        try require(migrated.preferences.fontSize == 15 && migrated.preferences.theme == .liquidGlass, "legacy appearance")
        let file = LibraryFile(url: root.appendingPathComponent("library.json"))
        try legacyBytes.write(to: file.url)
        let disk = LibraryDisk(file: file)
        let loaded = try await disk.load()
        try require(loaded.0 == migrated, "legacy disk migration")
        let archives = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Migrations"), includingPropertiesForKeys: nil)
        try require(archives.count == 1 && Data(contentsOf: archives[0]) == legacyBytes, "exact original migration archive")
        let manifest = try Data(contentsOf: file.url)
        try require(!String(decoding: manifest, as: UTF8.self).contains("核心结论"), "body is stored separately from manifest")
        print("PASS legacy migration, shortcut and untouched original archive")
        // Import a 17,000-character Chinese document, then reload after removing its source.
        let source = root.appendingPathComponent("source.md")
        let body = String(repeating: "长文测试。", count: 3400)
        try require(body.count == 17_000, "benchmark character count")
        try Data(body.utf8).write(to: source)
        var library = migrated
        let start = Date(), md = try MarkdownDocument.read(source)
        var prompt = Prompt(title: "大文件测试", body: try md.text, markdown: md)
        prompt.additionalMarkdown = [try MarkdownDocument(fileName: "source.md", data: Data("第二份独立附件".utf8))]
        prompt.syncMarkdownBody = false
        library.prompts.append(prompt)
        try await disk.save(library, revision: 1)
        let singleTime = elapsed(start)
        try FileManager.default.removeItem(at: source)
        let reload = Date()
        try require(try LibraryFile(url: file.url).load() == library, "separate files round-trip after source removal")
        print("BENCH 17,000 Chinese characters: read + decode + durable save \(singleTime)s; cold reload \(elapsed(reload))s")
        let firstURL = try file.markdownURL(for: prompt, document: md)
        let otherURL = try file.markdownURL(for: prompt, document: prompt.additionalMarkdown![0])
        try require(firstURL != otherURL && firstURL.lastPathComponent == "source.md", "same-name attachments are isolated")
        try require(Data(contentsOf: firstURL) == md.data, "export preserves original bytes")
        let timeBefore = try firstURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        library.prompts[library.prompts.count - 1].isFavorite.toggle()
        try await disk.save(library, revision: 3)
        try await disk.save(migrated, revision: 2)
        try require(try file.load() == library, "stale autosave cannot replace explicit flush")
        try require(try firstURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == timeBefore, "metadata change does not rewrite Markdown")
        print("PASS same-name files, stable assets, metadata-only writes, stale-revision guard")
        // Both revisions must remain complete after body edits and deletions.
        let previous = library
        library.prompts[library.prompts.count - 1].body = "新版正文"
        try await disk.save(library, revision: 4)
        try require(try file.loadBackup() == previous, "backup retains old immutable body")
        try require(try file.load() == library, "primary retains newer body")
        var corrupted = try JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as! [String: Any]
        var records = corrupted["prompts"] as! [[String: Any]]
        var asset = records[0]["body"] as! [String: Any]; asset["path"] = "Documents/../../outside.txt"
        records[0]["body"] = asset; corrupted["prompts"] = records
        try JSONSerialization.data(withJSONObject: corrupted).write(to: file.url, options: .atomic)
        do { _ = try file.load(); throw LibraryError.invalid("CHECK FAILED: traversal accepted") }
        catch let error as LibraryError { if error.localizedDescription.hasPrefix("CHECK FAILED") { throw error } }
        let damagedManifest = try Data(contentsOf: file.url)
        let recovered = try await LibraryDisk(file: LibraryFile(url: file.url)).load()
        try require(recovered.1 && recovered.0 == previous, "corrupt manifest recovers verified backup")
        let recoveryFiles = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
        try require(recoveryFiles.contains(where: { (try? Data(contentsOf: $0)) == damagedManifest }), "recovery preserves damaged original")
        print("PASS immutable backup, path validation and corrupt-primary recovery")
        // Batch fixture: 100 real files, 1.7 million Chinese characters, independent file reads.
        let batchRoot = root.appendingPathComponent("batch"), sources = root.appendingPathComponent("batch-sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        var urls: [URL] = []
        for i in 0..<100 { let url = sources.appendingPathComponent("prompt-\(i).md"); try Data((body + "\n\(i)").utf8).write(to: url); urls.append(url) }
        let batchStart = Date()
        let batchPrompts = try urls.map { url -> Prompt in let doc = try MarkdownDocument.read(url); return Prompt(title: doc.title, body: try doc.text, markdown: doc) }
        let batchFile = LibraryFile(url: batchRoot.appendingPathComponent("library.json"))
        let batchLibrary = PromptLibrary(categories: migrated.categories, prompts: batchPrompts)
        try batchFile.save(batchLibrary)
        let batchTime = elapsed(batchStart), batchReload = Date()
        try require(try LibraryFile(url: batchFile.url).load() == batchLibrary, "batch full-content round-trip")
        print("BENCH 100 Markdown files / ~1.7M Chinese characters: read + decode + durable save \(batchTime)s; cold reload \(elapsed(batchReload))s")
        let largeStart = Date()
        let largeText = String(repeating: body, count: 100)
        let largeDocument = try MarkdownDocument(fileName: "large.md", data: Data(largeText.utf8))
        let largeLibrary = PromptLibrary(categories: migrated.categories, prompts: [Prompt(title: "Large", body: try largeDocument.text, markdown: largeDocument)])
        let largeFile = LibraryFile(url: root.appendingPathComponent("large/library.json"))
        try largeFile.save(largeLibrary)
        try require(try LibraryFile(url: largeFile.url).load() == largeLibrary, "single 5.1 MB Markdown round-trip")
        print("BENCH single 5.1 MB Markdown: decode + durable save + cold reload \(elapsed(largeStart))s")
        let fast = Date(); for _ in 0..<100 { _ = batchLibrary.filtered(.all); _ = batchPrompts[0].excerpt }
        try require(batchPrompts[0].excerpt.count <= 280, "bounded list excerpt")
        print("BENCH 100 empty-query list refreshes + excerpts \(elapsed(fast))s")
        if let fixture = ProcessInfo.processInfo.environment["CIYU_LEGACY_FIXTURE"] {
            let original = try Data(contentsOf: URL(fileURLWithPath: fixture))
            let oldLibrary = try LibraryFile.decode(original)
            let fixtureFile = LibraryFile(url: root.appendingPathComponent("private-recovery/library.json"))
            try FileManager.default.createDirectory(at: fixtureFile.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try original.write(to: fixtureFile.url)
            let result = try await LibraryDisk(file: fixtureFile).load()
            try require(result.0 == oldLibrary, "private legacy fixture exact migration")
            try require(try fixtureFile.load() == oldLibrary, "private legacy fixture reload")
            print("PASS private legacy fixture: \(oldLibrary.prompts.count) prompts / \(oldLibrary.categories.count) categories; original location unchanged")
        }
        print("Storage checks completed.")
    }
}
