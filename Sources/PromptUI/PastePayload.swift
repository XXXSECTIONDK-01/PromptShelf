import AppKit

public enum PromptPastePayload {
    case text(String)
    case files([URL])

    @MainActor
    public func write(to pasteboard: NSPasteboard) -> Bool {
        switch self {
        case .text(let text):
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        case .files(let urls):
            guard !urls.isEmpty, urls.count <= 20, urls.allSatisfy({ url in
                guard url.isFileURL, let attributes = try? url.resourceValues(forKeys: [.isRegularFileKey]), attributes.isRegularFile == true else { return false }
                return FileManager.default.isReadableFile(atPath: url.path)
            }) else { return false }
            pasteboard.clearContents()
            return pasteboard.writeObjects(urls.map { $0 as NSURL })
        }
    }
}
