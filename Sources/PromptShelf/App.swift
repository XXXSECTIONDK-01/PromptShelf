import AppKit
import SwiftUI
import Combine
import PromptCore

@main
@MainActor
struct PromptShelfMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: AppStore!
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var hotkey: GlobalHotkey!
    private var quickPanel: QuickPanelController!
    private var appliedInterfaceScale: Double?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let demo = ProcessInfo.processInfo.arguments.contains("--demo") || Bundle.main.bundleIdentifier == "studio.promptshelf.preview"
        store = AppStore(demo: demo)
        quickPanel = QuickPanelController(store: store)
        quickPanel.showSettings = { [weak self] in self?.showBehavior() }
        store.openPanel = { [weak self] in self?.quickPanel.toggle() }
        hotkey = GlobalHotkey()
        hotkey.action = { [weak self] in self?.quickPanel.toggle() }
        store.updateHotkey = { [weak self] key in self?.hotkey.register(key) ?? false }
        store.recordingHotkey = { [weak self] active in self?.hotkey.setRecording(active) }
        if !store.isLoading && !hotkey.register(store.preferences.hotkey) {
            store.errorMessage = "全局快捷键注册失败。可通过菜单栏打开面板，或在设置中更换组合键。"
        }
        if let icon = AppIdentity.icon { NSApp.applicationIconImage = icon }
        buildMainMenu(); buildStatusMenu(); buildWindow()
        store.$library.map(\.preferences).removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateAppearance() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in
            DispatchQueue.main.async { self?.store.refreshAccessibility() }
        }.store(in: &subscriptions)
        showLibrary()
    }
    private var terminating = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !store.isImporting else { store.errorMessage = "正在导入文件，请等待完成后退出。"; showLibrary(); return .terminateCancel }
        guard !terminating else { return .terminateCancel }
        terminating = true; store.isClosing = true
        Task {
            do { try await store.flush(); sender.reply(toApplicationShouldTerminate: true) }
            catch {
                terminating = false; store.isClosing = false
                store.errorMessage = "退出前保存失败，应用保持打开。请导出备份后重试。\n\(error.localizedDescription)"
                showLibrary(); sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { hotkey.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showLibrary() }; return true
    }
    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "词屿 · PromptShelf"
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 1040, height: 680)
        let hostingView = NSHostingView(rootView: LibraryView(store: store))
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.appearance = store.appearance
        window.delegate = self
        updateInterfaceScale(initial: true)
        window.center()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
    @objc func showLibrary() {
        quickPanel?.hide(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func showAppearance() { store.page = .appearance; showLibrary() }
    func showBehavior() { store.page = .behavior; showLibrary() }
    @objc func showQuickPanel() { quickPanel.toggle() }
    @objc func newPrompt() { showLibrary(); store.newPrompt() }
    @objc func importMarkdown() { showLibrary(); store.chooseMarkdownFiles() }
    @objc func importPrompts() { showLibrary(); store.importLibrary() }
    @objc func exportPrompts() { showLibrary(); store.exportLibrary() }
    @objc func undo(_ sender: Any?) { store.undo() }
    private func updateAppearance() { window?.appearance = store.appearance; updateInterfaceScale(); quickPanel.updateAppearance() }
    private func updateInterfaceScale(initial: Bool = false) {
        guard let window, appliedInterfaceScale != store.preferences.uiScale else { return }
        let scale = store.preferences.uiScale
        appliedInterfaceScale = scale
        let bounds = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window.minSize = NSSize(width: min(1040 * scale, bounds.width), height: min(680 * scale, bounds.height))
        var frame = window.frame
        let top = frame.maxY
        frame.size = NSSize(width: min(max(initial ? 1120 * scale : frame.width, window.minSize.width), bounds.width),
                            height: min(max(initial ? 760 * scale : frame.height, window.minSize.height), bounds.height))
        frame.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - frame.width)
        frame.origin.y = min(max(top - frame.height, bounds.minY), bounds.maxY - frame.height)
        window.setFrame(frame, display: true)
    }
    private func item(_ title: String, _ selector: Selector?, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key); item.target = target ?? self
        return item
    }
    private func buildMainMenu() {
        let main = NSMenu()
        let app = NSMenu(title: "词屿")
        app.addItem(item("关于词屿", #selector(showAbout)))
        app.addItem(.separator())
        app.addItem(item("设置…", #selector(showAppearance), key: ","))
        app.addItem(.separator())
        app.addItem(item("隐藏词屿", #selector(NSApplication.hide(_:)), key: "h", target: NSApp))
        app.addItem(item("退出词屿", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        let appItem = NSMenuItem(); appItem.submenu = app; main.addItem(appItem)
        let file = NSMenu(title: "文件")
        file.addItem(item("新建提示词", #selector(newPrompt), key: "n"))
        file.addItem(item("导入 Markdown…", #selector(importMarkdown)))
        file.addItem(item("导入提示词库…", #selector(importPrompts)))
        file.addItem(item("导出提示词库…", #selector(exportPrompts)))
        file.addItem(.separator())
        let close = NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"); file.addItem(close)
        let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: ""); fileItem.submenu = file; main.addItem(fileItem)
        let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", #selector(undo(_:)), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key))
        }
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); editItem.submenu = edit; main.addItem(editItem)
        NSApp.mainMenu = main
    }
    @objc func showAbout() { store.page = .about; showLibrary() }
    private func buildStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "词屿 PromptShelf")
        let menu = NSMenu()
        menu.addItem(item("打开快捷面板", #selector(showQuickPanel)))
        menu.addItem(item("管理提示词", #selector(showLibrary)))
        menu.addItem(item("设置…", #selector(showAppearance)))
        menu.addItem(.separator())
        menu.addItem(item("退出词屿", #selector(NSApplication.terminate(_:)), target: NSApp))
        statusItem.menu = menu
    }
}
