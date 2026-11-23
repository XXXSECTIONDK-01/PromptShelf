import SwiftUI
import AppKit

/// TextKit lays out visible paragraphs lazily instead of measuring the whole document in SwiftUI.
public struct PromptTextPreview: NSViewRepresentable {
    public var text: String
    public var fontSize: Double
    public var contentID: UUID
    public init(text: String, fontSize: Double = 15, contentID: UUID) { self.text = text; self.fontSize = fontSize; self.contentID = contentID }
    public func makeCoordinator() -> Coordinator { Coordinator() }
    public final class Coordinator { var id: UUID?; var text = ""; var size: Double = 0 }
    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        ThinScroller.configure(scroll)
        let view = AnnotatedPromptTextView(frame: .zero)
        view.isEditable = false; view.isSelectable = true; view.isRichText = false
        view.drawsBackground = false; view.textColor = .labelColor
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 0, height: 8)
        view.layoutManager?.allowsNonContiguousLayout = true
        view.isContinuousSpellCheckingEnabled = false; view.isGrammarCheckingEnabled = false
        view.setAccessibilityLabel("提示词正文预览")
        scroll.documentView = view
        return scroll
    }
    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let c = context.coordinator, changed = c.id != contentID
        if changed || c.text != text || c.size != fontSize {
            let styled = WarmPromptText.make(text, fontSize: fontSize)
            view.textStorage?.setAttributedString(styled.text)
            (view as? AnnotatedPromptTextView)?.firstHeading = styled.firstHeading
            c.id = contentID; c.text = text; c.size = fontSize
            if changed { view.setSelectedRange(NSRange(location: 0, length: 0)); scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView) }
        }
    }
}
