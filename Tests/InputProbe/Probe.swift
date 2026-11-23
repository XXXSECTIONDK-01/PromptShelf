import AppKit

/// A disposable, local input receiver for manual end-to-end verification.
/// No permissions, networking, storage, or access to other applications.
@main
@MainActor
struct InputProbe {
    static func main() {
        let app = NSApplication.shared
        let delegate = ProbeDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var textView: NSTextView!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 400), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "词屿 · 专用填入测试"
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        scroll.hasVerticalScroller = true; scroll.autoresizingMask = [.width, .height]
        textView = NSTextView(frame: scroll.bounds)
        textView.isRichText = false; textView.font = .systemFont(ofSize: 16)
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.autoresizingMask = [.width, .height]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.string = "词屿跨应用填入验证\n光标之后："
        textView.setAccessibilityLabel("专用测试输入框")
        scroll.documentView = textView
        window.contentView = scroll; window.center()
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        appMenu()
        NSApp.activate()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    private func appMenu() {
        let root = NSMenu()
        let main = NSMenuItem(); main.submenu = NSMenu()
        main.submenu?.addItem(withTitle: "退出测试", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.addItem(main)
        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        edit.submenu = NSMenu(title: "编辑")
        for (name, action, key) in [("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.submenu?.addItem(withTitle: name, action: action, keyEquivalent: key)
        }
        root.addItem(edit); NSApp.mainMenu = root
    }
}
