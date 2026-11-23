import SwiftUI
import PromptUI

/// One roll is one entry, not every movement event while the pointer remains
/// inside the label. Monotonic timestamps make the streak independent of clocks.
struct BrandHoverSequence {
    private(set) var isInside = false
    private(set) var count = 0
    private var lastEntry: TimeInterval?
    mutating func update(inside: Bool, now: TimeInterval) -> Bool {
        guard inside != isInside else { return false }
        isInside = inside
        guard inside else { return false }
        if let lastEntry, now - lastEntry > 6 { count = 0 }
        lastEntry = now; count += 1
        if count > 10 { count = 0; return true }
        return false
    }
}

struct BrandWordmark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sequence = BrandHoverSequence()
    @State private var chinese = false
    @State private var eggToken: UUID?
    static let easterEggCaption = "不要再玩人家了啦"
    static let easterEggFace = "(＞﹏＜)"
    static let easterEgg = easterEggCaption + easterEggFace
    var body: some View {
        BrandWordmarkLabel(chinese: chinese, showEasterEgg: eggToken != nil)
        .onHover { inside in
            let triggered = sequence.update(inside: inside, now: ProcessInfo.processInfo.systemUptime)
            chinese = inside
            if triggered { showEgg() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PromptShelf · 词屿")
        .accessibilityValue(eggToken == nil ? "" : Self.easterEgg)
        .accessibilityAction(named: "切换品牌名称") {
            chinese.toggle()
            if sequence.update(inside: chinese, now: ProcessInfo.processInfo.systemUptime) { showEgg() }
        }
        .onDisappear { eggToken = nil }
    }
    private func showEgg() {
        let token = UUID(); eggToken = token
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            if eggToken == token { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { eggToken = nil } }
        }
    }
}

/// Stateless drawing keeps both languages and the decorative bubble in one
/// reusable layout; hover counting and timers stay in the parent.
struct BrandWordmarkLabel: View {
    var chinese: Bool
    var showEasterEgg: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let lineHeight: CGFloat = 19
    var body: some View {
        DisplaySynchronizedReel(chinese: chinese, reduceMotion: reduceMotion)
        .frame(maxWidth: .infinity, alignment: .leading).frame(height: lineHeight, alignment: .top)
        .clipped()
        .foregroundStyle(AppTypography.annotation)
        .contentShape(Rectangle())
        .overlay(alignment: .topLeading) {
            if showEasterEgg {
                VStack(alignment: .leading, spacing: 3) {
                    Text(BrandWordmark.easterEggCaption)
                    Text(BrandWordmark.easterEggFace).fixedSize()
                }.font(.system(size: 11))
                    .foregroundStyle(AppTypography.annotation)
                    .fixedSize(horizontal: false, vertical: true).padding(10)
                    .frame(width: 150, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppTypography.rule.opacity(0.6), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                    .offset(y: lineHeight + 6).allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }
}
