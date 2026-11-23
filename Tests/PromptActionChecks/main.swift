import AppKit
import SwiftUI
import PromptCore
import PromptUI

@MainActor
func runChecks() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    var checks = 0
    func check(_ value: Bool, _ name: String) {
        guard value else { fputs("FAIL \(name)\n", stderr); exit(1) }
        checks += 1; print("PASS \(name)")
    }
    // Uses an isolated pasteboard; never reads or replaces the user's clipboard.
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PromptShelf-ActionChecks-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let prompt = Prompt(title: "临时文件", body: "# 中文\n\n正文")
    let files = try InstantOutput.materialize(InstantOutput.markdownDocuments(for: prompt), in: root)
    check(PromptPastePayload.files(files).write(to: pasteboard), "Write Markdown as a file pasteboard item")
    let received = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly:true]) as? [URL]
    check(received == files && pasteboard.types?.contains(.fileURL) == true, "Recipients receive file URLs")
    check(try String(contentsOf: files[0], encoding: .utf8) == prompt.body, "Generated attachment preserves text")
    let another = try InstantOutput.materialize(InstantOutput.markdownDocuments(for: prompt), in: root)
    check(PromptPastePayload.files(files + another).write(to: pasteboard) && pasteboard.pasteboardItems?.count == 2, "Multiple attachments have separate file items")
    check(PromptPastePayload.text("临时正文").write(to: pasteboard) && pasteboard.string(forType:.string) == "临时正文", "Text output remains text")
    let missing = root.appendingPathComponent("missing.md")
    check(!PromptPastePayload.files([missing]).write(to: pasteboard) && pasteboard.string(forType:.string) == "临时正文", "Missing files preserve existing clipboard content")
    check(!PromptPastePayload.files([URL(string:"https://example.com/file.md")!]).write(to:pasteboard), "Remote URLs cannot masquerade as attachments")

    var edits = 0, exports = 0, menuOpen = false
    let row = MarkdownDragRow(label: "Test prompt", prepareFiles: { files }, click: {}, started: {}, ended: { _ in }, actions: [
        PromptRowAction("即时编辑…", symbol:"square.and.pencil") { edits += 1 },
        PromptRowAction("以 Markdown 文件输出", symbol:"doc.badge.arrow.up") { exports += 1 }
    ], menuChanged: { menuOpen = $0 }) { Text("Test prompt") }
    let host = NSHostingView(rootView: row)
    host.frame = NSRect(x:0,y:0,width:500,height:70)
    host.layoutSubtreeIfNeeded()
    func find(_ view: NSView) -> MarkdownDragRow<Text>.DragView? {
        if let result = view as? MarkdownDragRow<Text>.DragView { return result }
        for child in view.subviews { if let found = find(child) { return found } }
        return nil
    }
    guard let native = find(host), let event = NSEvent.mouseEvent(with:.rightMouseDown, location:.zero, modifierFlags:[], timestamp:0, windowNumber:0, context:nil, eventNumber:1, clickCount:1, pressure:1), let menu = native.menu(for:event) else {
        fputs("FAIL Native context menu was not created\n", stderr); exit(1)
    }
    check(menu.items.map(\.title) == ["即时编辑…","以 Markdown 文件输出"] && menuOpen, "Native right-click menu exposes both actions")
    for item in menu.items { if let action = item.action { NSApplication.shared.sendAction(action, to:item.target, from:item) } }
    check(edits == 1 && exports == 1, "Native menu routes actions to the correct prompt")
    native.menuDidClose(menu)
    check(!menuOpen, "Menu close restores panel lifecycle state")
    let longText = String(repeating: "长正文与换行。\n", count: 210_000)
    let preview = NSHostingView(rootView: PromptTextPreview(text: longText, fontSize: 15, contentID: UUID()))
    preview.sizingOptions = []
    preview.frame = NSRect(x: 0, y: 0, width: 530, height: 360)
    let started = Date(); preview.layoutSubtreeIfNeeded()
    func findText(_ view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        for child in view.subviews { if let found = findText(child) { return found } }
        return nil
    }
    guard let textView = findText(preview) else { check(false, "Native text preview exists"); return }
    check(textView.string == longText && !textView.isEditable && textView.isSelectable, "Large preview preserves complete selectable text")
    check(textView.layoutManager?.allowsNonContiguousLayout == true, "Large preview enables lazy TextKit layout")
    preview.frame.size.width = 780; preview.layoutSubtreeIfNeeded()
    check(textView.enclosingScrollView?.bounds.width == 780, "Native preview follows window width")
    print(String(format: "BENCH native large preview: %.3fs", Date().timeIntervalSince(started)))
    print("\(checks) prompt action checks passed without global clipboard access or input events.")
}
try MainActor.assumeIsolated { try runChecks() }
