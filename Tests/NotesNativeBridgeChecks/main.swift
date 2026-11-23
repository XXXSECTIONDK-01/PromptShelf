import AppKit
import OSAKit

// Exercises the shipping JXA through the real OSA marshaller and Notes' public
// dictionary. All Apple Events target THIS fixture process, never Notes.app.
func code(_ text: String) -> FourCharCode { text.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
final class Item {
    let kind: String, id: String
    var name: String, text: String
    weak var parent: Item?
    var children: [Item] = []
    var data = Data()
    init(_ kind: String, _ id: String, _ name: String, _ text: String = "", parent: Item? = nil) {
        self.kind = kind; self.id = id; self.name = name; self.text = text; self.parent = parent
        parent?.children.append(self)
    }
}
final class Fixture: NSObject {
    let root = Item("capp", "root", "Native fixture")
    var events = 0, conversions = 0, nextID = 0
    var failNextGet = false
    var accountNoteQueries = 0, containerQueries = 0
    var attachmentPolls = 0
    override init() {
        super.init()
        let account = Item("acct", "a", "iCloud", parent: root)
        let folder = Item("cfol", "f", "Notes", parent: account)
        let nested = Item("cfol", "nested", "Nested", parent: folder)
        _ = Item("note", "nested-note", "Nested title", "Nested title\nNested body", parent: nested)
        let note = Item("note", "n", "标题", "标题\n正文", parent: folder)
        let attachment = Item("atts", "md", "native.md", parent: note)
        attachment.data = Data("# 原生桥接附件\n\n正文".utf8)
        _ = Item("atts", "web", "website.url", parent: note)
    }
    func children(_ parent: Item, kind: String) -> [Item] {
        if kind == "note", parent.kind == "acct" {
            func notes(_ item: Item) -> [Item] { item.children.flatMap { $0.kind == "note" ? [$0] : notes($0) } }
            return notes(parent)
        }
        if kind == "atts", parent.id.hasPrefix("created-"), attachmentPolls > 0 {
            attachmentPolls -= 1; return []
        }
        return parent.children.filter { $0.kind == kind }
    }
    func resolve(_ descriptor: NSAppleEventDescriptor?) -> [Item] {
        guard let descriptor, let want = descriptor.forKeyword(code("want"))?.typeCodeValue else { return [root] }
        let selector = descriptor.forKeyword(code("seld"))
        let owners = resolve(descriptor.forKeyword(code("from")))
        if want == code("prop"), selector?.typeCodeValue == code("cntr") { return owners.compactMap(\.parent) }
        let kind = ["acct", "cfol", "note", "atts"].first { code($0) == want } ?? "unknown"
        let candidates = owners.flatMap { children($0, kind: kind) }
        let form = descriptor.forKeyword(code("form"))?.enumCodeValue
        if form == code("ID  ") { return candidates.filter { $0.id == selector?.stringValue } }
        if form == code("indx"), selector?.descriptorType != code("abso") {
            let index = Int(selector?.int32Value ?? 0) - 1
            return candidates.indices.contains(index) ? [candidates[index]] : []
        }
        return candidates
    }
    func reference(_ item: Item) -> NSAppleEventDescriptor {
        let result = NSAppleEventDescriptor.record()
        result.setDescriptor(NSAppleEventDescriptor(typeCode: code(item.kind)), forKeyword: code("want"))
        result.setDescriptor(NSAppleEventDescriptor(enumCode: code("ID  ")), forKeyword: code("form"))
        result.setDescriptor(NSAppleEventDescriptor(string: item.id), forKeyword: code("seld"))
        result.setDescriptor(item.parent?.kind == "capp" ? .null() : item.parent.map(reference) ?? .null(), forKeyword: code("from"))
        return result.coerce(toDescriptorType: code("obj "))!
    }
    func plural(_ descriptor: NSAppleEventDescriptor?) -> Bool {
        guard let descriptor else { return false }
        return descriptor.forKeyword(code("seld"))?.descriptorType == code("abso")
    }
    func values(_ items: [NSAppleEventDescriptor], plural: Bool) -> NSAppleEventDescriptor {
        if !plural { return items.first ?? .null() }
        let result = NSAppleEventDescriptor.list()
        for (index, item) in items.enumerated() { result.insert(item, at: index + 1) }
        return result
    }
    func property(_ item: Item, key: FourCharCode) -> NSAppleEventDescriptor {
        switch key {
        case code("ID  "): return NSAppleEventDescriptor(string: item.id)
        case code("pnam"): return NSAppleEventDescriptor(string: item.name)
        case code("text"), code("body"): return NSAppleEventDescriptor(string: item.text)
        case code("asmo"): return NSAppleEventDescriptor(date: Date(timeIntervalSince1970: 1_800_000_000))
        case code("pwpr"): return NSAppleEventDescriptor(boolean: false)
        case code("cntr"): return item.parent.map(reference) ?? .null()
        default: return .null()
        }
    }
    @objc func handle(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        events += 1
        let direct = event.paramDescriptor(forKeyword: code("----"))
        let result: NSAppleEventDescriptor
        switch event.eventID {
        case code("doex"):
            // Emulate Notes failing to coerce a unique-ID existence query.
            conversions += 1
            reply.setParam(NSAppleEventDescriptor(int32: -1700), forKeyword: code("errn"))
            reply.setParam(NSAppleEventDescriptor(string: "不能转换类型。"), forKeyword: code("errs"))
            return
        case code("getd"):
            if failNextGet {
                failNextGet = false
                reply.setParam(NSAppleEventDescriptor(int32: -1743), forKeyword: code("errn"))
                reply.setParam(NSAppleEventDescriptor(string: "Not authorized to send Apple events."), forKeyword: code("errs"))
                return
            }
            let from = direct?.forKeyword(code("from"))
            let propertyCode = direct?.forKeyword(code("seld"))?.typeCodeValue
            let isNoteCollection = direct?.forKeyword(code("want"))?.typeCodeValue == code("note")
                || from?.forKeyword(code("want"))?.typeCodeValue == code("note")
            let owner = isNoteCollection ? (direct?.forKeyword(code("want"))?.typeCodeValue == code("note") ? from : from?.forKeyword(code("from"))) : nil
            if owner?.forKeyword(code("want"))?.typeCodeValue == code("acct") {
                accountNoteQueries += 1
                reply.setParam(NSAppleEventDescriptor(int32: -1728), forKeyword: code("errn")); return
            }
            if propertyCode == code("cntr") {
                containerQueries += 1
                reply.setParam(NSAppleEventDescriptor(int32: -1728), forKeyword: code("errn")); return
            }
            if propertyCode == code("asmo"), resolve(from).contains(where: { $0.kind == "atts" }) {
                reply.setParam(NSAppleEventDescriptor(int32: -1728), forKeyword: code("errn")); return
            }
            if direct?.forKeyword(code("want"))?.typeCodeValue == code("prop") {
                let from = direct?.forKeyword(code("from"))
                let key = direct?.forKeyword(code("seld"))?.typeCodeValue ?? 0
                result = values(resolve(from).map { property($0, key: key) }, plural: plural(from))
            } else {
                result = values(resolve(direct).map(reference), plural: plural(direct))
            }
        case code("setd"):
            guard let owner = resolve(direct?.forKeyword(code("from"))).first,
                  direct?.forKeyword(code("seld"))?.typeCodeValue == code("body"),
                  let html = event.paramDescriptor(forKeyword: code("data"))?.stringValue else {
                reply.setParam(NSAppleEventDescriptor(int32: -1728), forKeyword: code("errn")); return
            }
            owner.text = html; owner.name = heading(html)
            result = .null()
        case code("save"):
            guard let attachment = resolve(direct).first, let url = event.paramDescriptor(forKeyword: code("kfil"))?.fileURLValue else {
                reply.setParam(NSAppleEventDescriptor(int32: -1700), forKeyword: code("errn")); return
            }
            do { try attachment.data.write(to: url); result = .null() }
            catch { reply.setParam(NSAppleEventDescriptor(int32: -10000), forKeyword: code("errn")); return }
        case code("crel"):
            let kindCode = event.paramDescriptor(forKeyword: code("kocl"))?.typeCodeValue
            let kind = ["cfol", "note", "atts"].first { code($0) == kindCode } ?? "unknown"
            guard let parent = resolve(event.paramDescriptor(forKeyword: code("insh"))).first else {
                reply.setParam(NSAppleEventDescriptor(int32: -1728), forKeyword: code("errn")); return
            }
            let props = event.paramDescriptor(forKeyword: code("prdt"))
            let path = event.paramDescriptor(forKeyword: code("data"))?.fileURLValue
            nextID += 1
            let html = props?.forKeyword(code("body"))?.stringValue ?? ""
            let name = kind == "note" ? heading(html) : props?.forKeyword(code("pnam"))?.stringValue ?? path?.lastPathComponent ?? "Untitled"
            let item = Item(kind, "created-\(nextID)", name, html, parent: parent)
            if let path { item.data = (try? Data(contentsOf: path)) ?? Data() }
            if kind == "atts" { attachmentPolls = 2 }
            // Notes may return a creation-time specifier that cannot be read.
            let stale = Item(kind, "stale-creation-reference", name); stale.parent = parent
            result = reference(stale)
        case code("delo"):
            for item in resolve(direct) { item.parent?.children.removeAll { $0 === item } }
            result = .null()
        default:
            reply.setParam(NSAppleEventDescriptor(int32: -1708), forKeyword: code("errn")); return
        }
        reply.setParam(result, forKeyword: code("----"))
    }
}
func heading(_ html: String) -> String {
    guard let a = html.range(of: "<h1>"), let b = html.range(of: "</h1>", range: a.upperBound..<html.endIndex) else { return html }
    return String(html[a.upperBound..<b.lowerBound])
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let fixture = Fixture()
for event in ["getd", "setd", "doex", "save", "crel", "delo"] {
    NSAppleEventManager.shared().setEventHandler(fixture, andSelector: #selector(Fixture.handle(_:reply:)), forEventClass: code("core"), andEventID: code(event))
}
let shippingURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/NotesBridge.js")
var shipping = try String(contentsOf: shippingURL, encoding: .utf8)
// Redirect only the external application target; keep the shipping implementation.
shipping = shipping.replacingOccurrences(of: "Application('com.apple.Notes')", with: "Application.currentApplication()")
shipping = shipping.replacingOccurrences(of: "function run(argv)", with: "function nativeBridgeRun(argv)")
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PromptShelf-NativeChecks-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let upload = directory.appendingPathComponent("upload.md")
try Data("# Native export\n".utf8).write(to: upload)
var checks = 0
func request(_ action: String, _ values: [String: Any] = [:], expectSuccess: Bool = true) throws -> [String: Any] {
    var body = values; body["action"] = action
    let url = directory.appendingPathComponent("request.json")
    try JSONSerialization.data(withJSONObject: body).write(to: url)
    let arguments = String(data: try JSONSerialization.data(withJSONObject: [url.path]), encoding: .utf8)!
    let script = OSAScript(source: shipping + "\nnativeBridgeRun(\(arguments));", language: OSALanguage(forName: "JavaScript"))
    var error: NSDictionary?
    let response = script.executeAndReturnError(&error)?.stringValue
    guard let data = response?.data(using: .utf8),
          let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any], !expectSuccess || envelope["ok"] as? Bool == true else {
        throw NSError(domain: "NativeBridgeChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(action) failed: \(error?.description ?? response ?? "no response")"])
    }
    return envelope
}
func check(_ value: @autoclosure () -> Bool, _ name: String) {
    guard value() else { fputs("FAIL \(name)\n", stderr); exit(1) }
    checks += 1; print("PASS \(name)")
}
do {
    let accounts = try request("accounts")["result"] as? [[String: Any]]
    check(accounts?.first?["name"] as? String == "iCloud", "Native account values")
    let folders = try request("folders", ["accountID": "a"])["result"] as? [[String: Any]]
    check(folders?.count == 2 && folders?.last?["path"] as? String == "Notes / Nested", "Native folders and nested paths")
    let page = try request("list", ["accountID": "a", "folderID": "f"])["result"] as? [String: Any]
    let entries = page?["entries"] as? [[String: Any]]
    check(entries?.first?["markdownCount"] as? Int == 1, "Native note list and attachment names")
    let note = try request("read", ["accountID": "a", "noteID": "n", "directory": directory.path])["result"] as? [String: Any]
    check(note?["plainText"] as? String == "标题\n正文" && note?["folderID"] as? String == "f", "Native text and container property chain")
    let savedMarkdown = try String(contentsOf: directory.appendingPathComponent("0.md"), encoding: .utf8)
    check(savedMarkdown == "# 原生桥接附件\n\n正文", "Native Markdown attachment save")
    let result = try request("export", ["accountID": "a", "title": "Native export", "html": "<h1>Native export</h1><pre>Body</pre>", "files": [["name": "upload.md", "path": upload.path]]])["result"] as? [String: Any]
    check(result?["noteID"] as? String != nil, "Native folder, note and attachment creation")
    let managed = fixture.root.children[0].children.first { $0.name == "词屿" }
    check(managed?.children.first?.children.first?.data == Data("# Native export\n".utf8), "Native exported attachment data")
    let plain = try request("export", ["accountID":"a", "title":"Plain export", "html":"<h1>Plain export</h1><pre>Only text</pre>", "files":[]])["result"] as? [String:Any]
    check(plain?["noteID"] as? String != nil && managed?.children.last?.name == "Plain export", "Native plain-text export with stale creation reference")
    check(fixture.accountNoteQueries == 0 && fixture.containerQueries == 0, "Avoid unavailable account-wide notes and container references")
    check(fixture.events > 20 && fixture.conversions == 0, "No unique-ID existence coercion calls")
    fixture.failNextGet = true
    let denied = try request("accounts", expectSuccess: false)["error"] as? [String: Any]
    check(denied?["code"] as? Int == -1743 && (denied?["message"] as? String)?.contains("读取备忘录账户") == true, "Native Apple Event errorNumber and action context")
    print("\(checks) native OSA checks passed; events target the fixture process only.")
} catch { fputs("FAIL \(error)\n", stderr); exit(1) }
