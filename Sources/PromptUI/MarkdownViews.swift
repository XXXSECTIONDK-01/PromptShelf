import AppKit
import SwiftUI
import PromptCore

public struct PromptRowAction {
    public var title: String
    public var symbol: String
    public var perform: () -> Void
    public init(_ title: String, symbol: String, perform: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.perform = perform
    }
}

/// File rows distinguish a click from a drag, and keep the panel alive until AppKit ends the session.
public struct MarkdownDragRow<Content: View>: NSViewRepresentable {
    var label: String
    var prepare: () -> [URL]?
    var click: () -> Void
    var started: () -> Void
    var ended: (Bool) -> Void
    var actions: [PromptRowAction] = []
    var menuChanged: (Bool) -> Void = { _ in }
    @ViewBuilder var content: Content
    public init(label: String, prepare: @escaping () -> URL?, click: @escaping () -> Void, started: @escaping () -> Void, ended: @escaping (Bool) -> Void, @ViewBuilder content: () -> Content) {
        self.label = label; self.prepare = { prepare().map { [$0] } }; self.click = click; self.started = started; self.ended = ended; self.content = content()
    }
    public init(label: String, prepareFiles: @escaping () -> [URL]?, click: @escaping () -> Void, started: @escaping () -> Void, ended: @escaping (Bool) -> Void, actions: [PromptRowAction] = [], menuChanged: @escaping (Bool) -> Void = { _ in }, @ViewBuilder content: () -> Content) {
        self.label = label; self.prepare = prepareFiles; self.click = click; self.started = started; self.ended = ended; self.content = content()
        self.actions = actions; self.menuChanged = menuChanged
    }
    public func makeNSView(context: Context) -> DragView { DragView(rootView: content) }
    public func updateNSView(_ view: DragView, context: Context) {
        view.host.rootView = content
        view.prepare = prepare; view.clicked = click; view.started = started; view.ended = ended
        view.actions = actions; view.menuChanged = menuChanged
        view.setAccessibilityLabel(label)
        view.toolTip = actions.isEmpty ? "点击填入正文；拖动添加 Markdown 文件" : "点击填入正文；右键即时编辑或输出 Markdown；拖动添加文件"
    }
    public final class DragView: NSView, NSDraggingSource, NSMenuDelegate {
        let host: NSHostingView<Content>
        var prepare: (() -> [URL]?)?
        var clicked: (() -> Void)?
        var started: (() -> Void)?
        var ended: ((Bool) -> Void)?
        var actions: [PromptRowAction] = []
        var menuChanged: ((Bool) -> Void)?
        private var downPoint: NSPoint?
        private var dragging = false
        init(rootView: Content) {
            host = NSHostingView(rootView: rootView)
            host.sizingOptions = []
            super.init(frame: .zero)
            host.autoresizingMask = [.width, .height]; addSubview(host)
            setAccessibilityElement(true); setAccessibilityRole(.button)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        public override func layout() { super.layout(); host.frame = bounds }
        public override func menu(for event: NSEvent) -> NSMenu? {
            guard !actions.isEmpty else { return super.menu(for: event) }
            downPoint = nil
            menuChanged?(true)
            let menu = NSMenu(); menu.delegate = self
            for (index, action) in actions.enumerated() {
                let item = NSMenuItem(title: action.title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
                item.tag = index; item.target = self
                item.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
                menu.addItem(item)
            }
            return menu
        }
        @objc private func performMenuAction(_ item: NSMenuItem) {
            guard actions.indices.contains(item.tag) else { return }
            actions[item.tag].perform()
        }
        public func menuDidClose(_ menu: NSMenu) { menuChanged?(false) }
        public override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
        public override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control), let menu = menu(for: event) {
                NSMenu.popUpContextMenu(menu, with: event, for: self); return
            }
            downPoint = convert(event.locationInWindow, from: nil); dragging = false
        }
        public override func mouseDragged(with event: NSEvent) {
            guard !dragging, let downPoint else { return }
            let point = convert(event.locationInWindow, from: nil)
            guard hypot(point.x - downPoint.x, point.y - downPoint.y) >= 5 else { return }
            self.downPoint = nil
            guard let urls = prepare?(), !urls.isEmpty else { return }
            let items = urls.enumerated().map { index, url -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: url.path); icon.size = NSSize(width: 48, height: 48)
                item.setDraggingFrame(NSRect(x: point.x - 24 + CGFloat(index * 3), y: point.y - 24, width: 48, height: 48), contents: icon)
                return item
            }
            dragging = true; started?()
            let session = beginDraggingSession(with: items, event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
        }
        public override func mouseUp(with event: NSEvent) {
            if downPoint != nil, !dragging, bounds.contains(convert(event.locationInWindow, from: nil)) { clicked?() }
            downPoint = nil
        }
        public override func accessibilityPerformPress() -> Bool { clicked?(); return true }
        public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
        public func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
        public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            dragging = false; downPoint = nil; ended?(operation.contains(.copy))
        }
    }
}

public struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var importFile: (URL) -> Void
    var focus: Bool
    var acceptsFiles: Bool
    public init(text: Binding<String>, focus: Bool = false, acceptsFiles: Bool = true, importFile: @escaping (URL) -> Void) {
        self._text = text; self.focus = focus; self.acceptsFiles = acceptsFiles; self.importFile = importFile
    }
    public func makeCoordinator() -> Coordinator { Coordinator(self) }
    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 240))
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.borderType = .noBorder
        ThinScroller.configure(scroll)
        let view = DropTextView(frame: scroll.contentView.bounds)
        view.layoutManager?.allowsNonContiguousLayout = true
        view.isContinuousSpellCheckingEnabled = false; view.isGrammarCheckingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false; view.isAutomaticDataDetectionEnabled = false
        view.isRichText = false; view.allowsUndo = true; view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.font = .systemFont(ofSize: 15); view.textColor = .labelColor
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.textContainerInset = NSSize(width: 10, height: 12)
        view.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        let paragraph = AppTypography.paragraph(fontSize: 15)
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = [.font: NSFont.systemFont(ofSize: 15), .paragraphStyle: paragraph, .foregroundColor: NSColor.labelColor]
        view.string = text; view.delegate = context.coordinator
        view.acceptsFiles = acceptsFiles
        if acceptsFiles { view.registerForDraggedTypes([.fileURL]) }
        view.setAccessibilityLabel(acceptsFiles ? "提示词正文，可拖入 Markdown 文件" : "即时编辑正文，仅本次填入")
        scroll.documentView = view
        if focus { DispatchQueue.main.async { if let window = view.window { window.makeFirstResponder(view) } } }
        return scroll
    }
    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? DropTextView else { return }
        view.importFile = importFile
        view.acceptsFiles = acceptsFiles
        if view.string != text { view.string = text }
    }
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor
        init(_ parent: MarkdownTextEditor) { self.parent = parent }
        public func textDidChange(_ notification: Notification) {
            if let view = notification.object as? NSTextView { parent.text = view.string }
        }
    }
    public final class DropTextView: NSTextView {
        var importFile: ((URL) -> Void)?
        var acceptsFiles = true
        private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
            (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        }
        public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            let urls = fileURLs(sender)
            if !acceptsFiles, !urls.isEmpty { return [] }
            if !urls.isEmpty { return urls.count == 1 && MarkdownDocument.isSupported(urls[0]) ? .copy : [] }
            return super.draggingEntered(sender)
        }
        public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
        public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let urls = fileURLs(sender)
            if !acceptsFiles, !urls.isEmpty { return false }
            guard !urls.isEmpty else { return super.performDragOperation(sender) }
            guard urls.count == 1, MarkdownDocument.isSupported(urls[0]) else { return false }
            importFile?(urls[0]); return true
        }
    }
}
