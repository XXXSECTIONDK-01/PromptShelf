import SwiftUI
import AppKit
import PromptUI

/// Scale both measurement and rendering, so larger controls receive real space
/// and native text views keep their normal layout and event coordinate system.
struct InterfaceScaleLayout: Layout {
    var scale: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let logical = ProposedViewSize(width: proposal.width.map { $0 / scale }, height: proposal.height.map { $0 / scale })
        let size = content.sizeThatFits(logical)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                             proposal: ProposedViewSize(width: bounds.width / scale, height: bounds.height / scale))
    }
}

struct InterfaceScale: ViewModifier {
    var scale: Double
    func body(content: Content) -> some View {
        InterfaceScaleLayout(scale: scale) {
            content.scaleEffect(scale, anchor: .topLeading)
        }
        .background(ThinScrollbars())
    }
}

/// Fit the editor vertically by giving its text area less space, while keeping
/// the scaled title, metadata and Save button visible on smaller displays.
struct ScaledPromptSheet<Content: View>: View {
    var scale: Double
    var content: (CGFloat) -> Content
    init(scale: Double, @ViewBuilder content: @escaping (CGFloat) -> Content) {
        self.scale = scale; self.content = content
    }
    var body: some View {
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let logicalHeight = min(720, (screen.height - 100) / scale)
        content(logicalHeight).modifier(InterfaceScale(scale: scale))
    }
}
