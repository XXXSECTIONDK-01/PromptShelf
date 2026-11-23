import AppKit
import SwiftUI

/// Warm annotations, with Songti reserved for titles. Surfaces and control tints
/// continue to come from the existing appearance and category preferences.
public enum AppTypography {
    public static func titleNSFont(size: CGFloat) -> NSFont {
        if let songti = NSFont(name: "SongtiSC-Bold", size: size) ?? NSFont(name: "STSongti-SC-Bold", size: size) { return songti }
        let system = NSFont.systemFont(ofSize: size, weight: .semibold)
        return system.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? system
    }
    public static func title(_ size: CGFloat) -> Font { Font(titleNSFont(size: size)) }
    public static let annotationNS = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.88, green: 0.69, blue: 0.49, alpha: 1)
            : NSColor(calibratedRed: 0.67, green: 0.46, blue: 0.27, alpha: 1)
    }
    public static let ruleNS = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.67, green: 0.48, blue: 0.30, alpha: 1)
            : NSColor(calibratedRed: 0.90, green: 0.74, blue: 0.56, alpha: 1)
    }
    public static let emphasisNS = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.91, green: 0.73, blue: 0.55, alpha: 1)
            : NSColor(calibratedRed: 0.58, green: 0.36, blue: 0.18, alpha: 1)
    }
    public static var annotation: Color { Color(nsColor: annotationNS) }
    public static var rule: Color { Color(nsColor: ruleNS) }
    public static func paragraph(fontSize: CGFloat) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = fontSize * 1.9
        return paragraph
    }
}

public struct WarmSectionLabel: View {
    private var title: String
    public init(_ title: String) { self.title = title }
    public var body: some View {
        Text(title).font(.system(size: 10, weight: .medium)).tracking(1.2)
            .foregroundStyle(AppTypography.annotation)
    }
}

public struct WarmHeading: View {
    private var title: String
    private var size: CGFloat
    public init(_ title: String, size: CGFloat = 16) { self.title = title; self.size = size }
    public var body: some View {
        Text(title).font(AppTypography.title(size)).underline(true, color: AppTypography.rule)
    }
}

/// Styles the original string in place: copying, dragging and exporting still
/// use the exact source. Regex scans do not ask TextKit to lay out the document.
public enum WarmPromptText {
    private static let headings = try! NSRegularExpression(pattern: "(?m)^ {0,3}(?:(`{3,}|~{3,}).*|(#{1,6})[ \\t]+(.+))$")
    private static let bold = try! NSRegularExpression(pattern: "\\*\\*[^\\r\\n*]+\\*\\*")
    public struct Result {
        public let text: NSAttributedString
        public let firstHeading: NSRange?
    }
    public static func make(_ source: String, fontSize: CGFloat) -> Result {
        let string = source as NSString
        let all = NSRange(location: 0, length: string.length)
        let output = NSMutableAttributedString(string: source, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.labelColor,
            .paragraphStyle: AppTypography.paragraph(fontSize: fontSize)
        ])
        var fence: (marker: unichar, count: Int, start: Int)?
        var code: [NSRange] = []
        var firstHeading: NSRange?
        var titleRanges: [NSRange] = []
        headings.enumerateMatches(in: source, range: all) { match, _, _ in
            guard let match else { return }
            if match.range(at: 1).location != NSNotFound {
                let range = match.range(at: 1), marker = string.character(at: range.location)
                if let open = fence {
                    if marker == open.marker && range.length >= open.count {
                        let remainder = string.substring(with: NSRange(location: NSMaxRange(range), length: NSMaxRange(match.range) - NSMaxRange(range))).trimmingCharacters(in: .whitespaces)
                        if remainder.isEmpty {
                            code.append(NSRange(location: open.start, length: NSMaxRange(match.range) - open.start)); fence = nil
                        }
                    }
                } else { fence = (marker, range.length, match.range.location) }
            } else if fence == nil {
                let headingSize = fontSize + (match.range(at: 2).length == 1 ? 6 : 3)
                output.addAttributes([.font: AppTypography.titleNSFont(size: headingSize),
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: AppTypography.ruleNS], range: match.range(at: 3))
                // Keep the visible Markdown syntax quiet, without hiding characters.
                output.addAttribute(.foregroundColor, value: AppTypography.annotationNS, range: match.range(at: 2))
                titleRanges.append(match.range(at: 3))
                if firstHeading == nil { firstHeading = match.range(at: 3) }
            }
        }
        if let fence { code.append(NSRange(location: fence.start, length: all.length - fence.start)) }
        var codeIndex = 0, titleIndex = 0
        bold.enumerateMatches(in: source, range: all) { match, _, _ in
            guard let match else { return }
            while codeIndex < code.count && NSMaxRange(code[codeIndex]) <= match.range.location { codeIndex += 1 }
            guard codeIndex == code.count || NSIntersectionRange(code[codeIndex], match.range).length == 0 else { return }
            while titleIndex < titleRanges.count && NSMaxRange(titleRanges[titleIndex]) <= match.range.location { titleIndex += 1 }
            output.addAttribute(.foregroundColor, value: AppTypography.emphasisNS, range: match.range)
            if titleIndex == titleRanges.count || NSIntersectionRange(titleRanges[titleIndex], match.range).length == 0 {
                output.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize, weight: .semibold), range: match.range)
            }
        }
        return Result(text: output, firstHeading: firstHeading)
    }
}

final class AnnotatedPromptTextView: NSTextView {
    var firstHeading: NSRange?
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let heading = firstHeading, let manager = layoutManager, let container = textContainer else { return }
        let origin = textContainerOrigin
        let visible = visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = manager.glyphRange(forBoundingRect: visible, in: container)
        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let end = NSMaxRange(heading) - 1
        guard end >= 0, NSLocationInRange(end, characters) else { return }
        let last = manager.glyphRange(forCharacterRange: NSRange(location: end, length: 1), actualCharacterRange: nil)
        let rect = manager.boundingRect(forGlyphRange: last, in: container).offsetBy(dx: origin.x, dy: origin.y)
        let note = NSAttributedString(string: "重点", attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: AppTypography.annotationNS])
        let point = NSPoint(x: rect.maxX + 8, y: max(rect.minY - 2, 0))
        if point.x + note.size().width < visibleRect.maxX - 5 { note.draw(at: point) }
    }
}
