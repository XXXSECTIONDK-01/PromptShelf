import AppKit
import SwiftUI

/// Keep AppKit's hit testing, thumb tracking, accessibility and overlay fading.
/// Only the painted thumb is narrower; its native interaction area is retained.
public final class ThinScroller: NSScroller {
    public override class var isCompatibleWithOverlayScrollers: Bool { self == ThinScroller.self }
    public var paintedKnobRect: NSRect {
        let knob = rect(for: .knob)
        guard !knob.isEmpty else { return .zero }
        let vertical = bounds.height >= bounds.width
        return vertical
            ? NSRect(x: knob.midX - 1.5, y: knob.minY, width: 3, height: knob.height)
            : NSRect(x: knob.minX, y: knob.midY - 1.5, width: knob.width, height: 3)
    }
    public override func drawKnob() {
        let rect = paintedKnobRect
        guard !rect.isEmpty else { return }
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        NSColor.labelColor.withAlphaComponent(contrast ? 0.75 : 0.32).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
    }
    public override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    public static func configure(_ scroll: NSScrollView) {
        if let existing = scroll.verticalScroller, !(existing is ThinScroller) {
            let replacement = ThinScroller(frame: existing.frame)
            replacement.controlSize = .small
            scroll.verticalScroller = replacement
        }
        if let existing = scroll.horizontalScroller, !(existing is ThinScroller) {
            let replacement = ThinScroller(frame: existing.frame)
            replacement.controlSize = .small
            scroll.horizontalScroller = replacement
        }
        if scroll.scrollerStyle != .overlay { scroll.scrollerStyle = .overlay }
        if !scroll.autohidesScrollers { scroll.autohidesScrollers = true }
    }
}

/// Configure scroll views created internally by SwiftUI, scoped to this window.
/// Updates follow layout and system style changes, without polling or changing
/// the user's global scroll-bar preference.
public struct ThinScrollbars: NSViewRepresentable {
    public init() {}
    public func makeNSView(context: Context) -> NSView { ScrollbarProbe() }
    public func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollbarProbe)?.schedule()
    }
}

private final class ScrollbarProbe: NSView {
    private var pending = false
    private var observer: NSObjectProtocol?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        observer = NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.schedule()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); schedule() }
    override func layout() { super.layout(); schedule() }
    func schedule() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pending = false
            guard let root = self.window?.contentView else { return }
            self.configureTree(root)
        }
    }
    private func configureTree(_ view: NSView) {
        if let scroll = view as? NSScrollView { ThinScroller.configure(scroll) }
        for child in view.subviews { configureTree(child) }
    }
}
