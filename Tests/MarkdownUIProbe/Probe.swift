import AppKit
import SwiftUI
import PromptCore
import PromptUI

@main
@MainActor
struct MarkdownUIProbe {
    static func main() {
        let app = NSApplication.shared; let delegate = ProbeDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 650), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "词屿 · Markdown 拖放验证"
        window.contentView = NSHostingView(rootView: ProbeView())
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate()
        let menu = NSMenu(); let item = NSMenuItem(); item.submenu = NSMenu()
        item.submenu?.addItem(withTitle: "退出验证", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(item); NSApp.mainMenu = menu
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
struct ProbeView: View {
    @State private var text = ""
    @State private var status = "等待拖放"
    @State private var transfer = "等待接收文件"
    private let document = try! MarkdownDocument(fileName: "Markdown-拖放验证.md", data: Data("# Markdown 拖放验证\n\n中文正文与 **Markdown** 格式。\n".utf8))
    private let promptID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Markdown 原生拖放验证").font(.title2)
            MarkdownDragRow(label: "拖动测试 Markdown 文件", prepare: {
                try? document.materialize(in: FileManager.default.temporaryDirectory.appendingPathComponent("PromptShelf-DragProbe"), promptID: promptID)
            }, click: { status = "点击事件有效" }, started: { status = "拖放进行中" }, ended: { status = $0 ? "文件已接收 · copy" : "拖放已取消" }) {
                HStack { Image(systemName: "doc.text"); Text(document.fileName); Spacer(); Text("拖动文件") }
                    .font(.system(size: 15)).padding(16).background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }.frame(height: 58).frame(maxWidth: .infinity)
            Text("正文导入目标（生产环境使用的编辑器）").font(.headline)
            MarkdownTextEditor(text: $text) { url in
                do { text = try MarkdownDocument.read(url).text; status = "正文已读取" }
                catch { status = error.localizedDescription }
            }.frame(height: 180).background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            Text("文件附件目标（验证文件 URL 与实际内容）").font(.headline)
            FileReceiver { name, body in transfer = "已接收附件：\(name)\n\(body)" }.frame(height: 115)
            Text(transfer).font(.system(size: 13)).lineLimit(4).textSelection(.enabled)
            Text(status).font(.system(size: 13, weight: .medium)).foregroundStyle(.blue)
            Spacer(minLength: 0)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
private struct FileReceiver: NSViewRepresentable {
    var received: (String, String) -> Void
    func makeNSView(context: Context) -> Receiver { Receiver() }
    func updateNSView(_ view: Receiver, context: Context) { view.received = received }
    final class Receiver: NSView {
        var received: ((String, String) -> Void)?
        override init(frame: NSRect) {
            super.init(frame: frame); registerForDraggedTypes([.fileURL]); setAccessibilityElement(true); setAccessibilityLabel("Markdown 附件接收区域")
        }
        required init?(coder: NSCoder) { fatalError() }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.controlBackgroundColor.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
            ("将上方文件拖到此处" as NSString).draw(at: NSPoint(x: 20, y: 40), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.secondaryLabelColor])
        }
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : [] }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], let url = urls.first,
                  let document = try? MarkdownDocument.read(url), let body = try? document.text else { return false }
            received?(document.fileName, body); return true
        }
    }
}
