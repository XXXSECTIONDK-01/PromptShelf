import AppKit
import SwiftUI
import QuartzCore

/// No hard-coded 60/120 Hz ceiling. A 144/240 Hz screen is allowed to use its
/// own cadence; macOS retains final control for power and thermal policies.
public enum DisplayCadence {
    public static func range(maximumFramesPerSecond maximum: Int, lowPower: Bool) -> CAFrameRateRange {
        guard maximum > 0 else { return .default }
        let highest = Float(maximum)
        let preferred = lowPower ? min(60, highest) : highest
        return CAFrameRateRange(minimum: min(60, preferred), maximum: preferred, preferred: preferred)
    }
}

/// Time-based progress, so changing frame rate never changes animation speed.
public struct DisplayTransition {
    public var from: CGFloat
    public var to: CGFloat
    public var started: CFTimeInterval
    public var duration: CFTimeInterval
    public init(from: CGFloat, to: CGFloat, started: CFTimeInterval, duration: CFTimeInterval = 0.28) {
        self.from = from; self.to = to; self.started = started; self.duration = duration
    }
    public func value(at time: CFTimeInterval) -> CGFloat {
        let t = min(1, max(0, (time - started) / max(duration, .leastNonzeroMagnitude)))
        let eased = t * t * (3 - 2 * t)
        return from + (to - from) * eased
    }
    public func isFinished(at time: CFTimeInterval) -> Bool { time >= started + duration }
}

/// Only the small custom brand animation has a display link. AppKit scrolling
/// and SwiftUI animations keep their system frame pacing; idle views don't tick.
public struct DisplaySynchronizedReel: NSViewRepresentable {
    public var chinese: Bool
    public var reduceMotion: Bool
    public init(chinese: Bool, reduceMotion: Bool) { self.chinese = chinese; self.reduceMotion = reduceMotion }
    public func makeNSView(context: Context) -> ReelView { ReelView() }
    public func updateNSView(_ view: ReelView, context: Context) { view.show(chinese: chinese, animated: !reduceMotion) }
    public static func dismantleNSView(_ view: ReelView, coordinator: ()) { view.stop() }

    public final class ReelView: NSView {
        private var progress: CGFloat = 0
        private var target: CGFloat = 0
        private var initialized = false
        private var transition: DisplayTransition?
        private var link: CADisplayLink?
        private var observers: [NSObjectProtocol] = []
        private let proxy = LinkTarget()
        private let lineHeight: CGFloat = 19
        public var hasActiveDisplayLink: Bool { link != nil }
        public override var isFlipped: Bool { true }
        public override var isOpaque: Bool { false }
        public override func hitTest(_ point: NSPoint) -> NSView? { nil }
        public override init(frame frameRect: NSRect) { super.init(frame: frameRect); proxy.view = self }
        public required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        deinit { link?.invalidate(); observers.forEach { NotificationCenter.default.removeObserver($0) } }
        public func show(chinese: Bool, animated: Bool) {
            let desired: CGFloat = chinese ? 1 : 0
            guard !initialized || desired != target || (!animated && link != nil) else { return }
            let first = !initialized
            initialized = true; target = desired
            guard !first, animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                  let window, window.isVisible, window.occlusionState.contains(.visible) else { finish(); return }
            let now = CACurrentMediaTime()
            if let transition { progress = transition.value(at: now) }
            transition = DisplayTransition(from: progress, to: desired, started: now, duration: 0.28 * abs(desired - progress))
            if link == nil {
                let displayLink = self.displayLink(target: proxy, selector: #selector(LinkTarget.step(_:)))
                link = displayLink
                updateRange()
                displayLink.add(to: .main, forMode: .common)
            }
        }
        public func stop() { link?.invalidate(); link = nil; transition = nil }
        private func finish() { stop(); progress = target; needsDisplay = true }
        fileprivate func step(_ sender: CADisplayLink) {
            guard let transition, let window, window.isVisible, window.occlusionState.contains(.visible) else { finish(); return }
            updateRange()
            // targetTimestamp is the presentation deadline, not a frame count.
            let time = max(sender.timestamp, sender.targetTimestamp)
            progress = transition.value(at: time); needsDisplay = true
            if transition.isFinished(at: time) { finish() }
        }
        private func updateRange() {
            let desired = DisplayCadence.range(maximumFramesPerSecond: window?.screen?.maximumFramesPerSecond ?? 0, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
            if let link, link.preferredFrameRateRange != desired { link.preferredFrameRateRange = desired }
        }
        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); finish()
            observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
            guard let window else { return }
            for name in [NSWindow.didChangeScreenNotification, NSWindow.didChangeOcclusionStateNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    guard let self else { return }
                    if self.window?.occlusionState.contains(.visible) != true { self.finish() }
                    else { self.updateRange() }
                })
            }
        }
        public override func draw(_ dirtyRect: NSRect) {
            let english = NSAttributedString(string: "PromptShelf", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: AppTypography.annotationNS])
            let chinese = NSAttributedString(string: "词屿", attributes: [.font: AppTypography.titleNSFont(size: 15), .kern: 2, .foregroundColor: AppTypography.annotationNS])
            for (index, text) in [english, chinese].enumerated() {
                let y = CGFloat(index) * lineHeight + (lineHeight - text.size().height) / 2 - progress * lineHeight
                text.draw(at: NSPoint(x: 0, y: y))
            }
        }
    }
    private final class LinkTarget: NSObject {
        weak var view: ReelView?
        @objc func step(_ link: CADisplayLink) { view?.step(link) }
    }
}
