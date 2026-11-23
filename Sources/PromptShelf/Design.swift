import SwiftUI
import AppKit
import PromptCore

enum ColorToken: String, CaseIterable {
    case blue, violet, green, orange, rose, gray
    var color: Color {
        switch self {
        case .blue: return Color(hex: 0x2A73F0)
        case .violet: return Color(hex: 0x5A5CD9)
        case .green: return Color(hex: 0x17A398)
        case .orange: return Color(hex: 0xED822E)
        case .rose: return Color(hex: 0xE0517F)
        case .gray: return Color(hex: 0x6B7078)
        }
    }
    var title: String {
        switch self { case .blue: return "海蓝"; case .violet: return "鸢紫"; case .green: return "松绿"; case .orange: return "暖砂"; case .rose: return "蔷薇"; case .gray: return "石墨" }
    }
    static func color(_ value: String) -> Color { (Self(rawValue: value) ?? .blue).color }
    static func categoryLabel(_ value: String, selected: Bool) -> Color {
        let original = color(value)
        // Retain the category hue against blue selection while lifting contrast.
        guard selected else { return original }
        return Color(nsColor: NSColor(original).blended(withFraction: 0.78, of: .white) ?? NSColor(original))
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = material
        view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

struct BrandMark: View {
    var size: CGFloat = 40
    var body: some View {
        Group {
            if let icon = AppIdentity.icon { Image(nsImage: icon).resizable().interpolation(.high).scaledToFit() }
            else { Image(systemName: "app").resizable().scaledToFit().foregroundStyle(.secondary) }
        }.frame(width: size, height: size).accessibilityLabel("词屿应用图标")
    }
}

struct CategoryIcon: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 26
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: size * 0.25))
    }
}

struct Keycap: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary).padding(.horizontal, 5).padding(.vertical, 3)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.07), lineWidth: 0.5))
    }
}

struct IconButton: View {
    var symbol: String
    var help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13)).frame(width: 28, height: 28).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help(help).accessibilityLabel(help)
    }
}

struct SurfaceCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.06), lineWidth: 1))
    }
}

struct EmptyState: View {
    var symbol: String = "text.bubble"
    var title: String
    var detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 15, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NativeSearch: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = "搜索提示词"
    var focus: Bool = false
    var fontSize: CGFloat = 14
    var command: ((String) -> Bool)?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder; field.font = .systemFont(ofSize: fontSize)
        field.focusRingType = .none; field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel(placeholder)
        if focus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak field] in
                guard let field, let window = field.window else { return }
                window.makeFirstResponder(field)
            }
        }
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if field.font?.pointSize != fontSize { field.font = .systemFont(ofSize: fontSize) }
    }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearch
        init(_ parent: NativeSearch) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField { parent.text = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            return parent.command?(NSStringFromSelector(commandSelector)) ?? false
        }
    }
}

extension Hotkey {
    var display: String {
        var text = ""
        if modifiers & 4096 != 0 { text += "⌃" }
        if modifiers & 2048 != 0 { text += "⌥" }
        if modifiers & 512 != 0 { text += "⇧" }
        if modifiers & 256 != 0 { text += "⌘" }
        let names: [UInt32: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",36:"↩",48:"⇥",49:"空格",51:"⌫",53:"⎋",76:"⌤",115:"↖",116:"⇞",117:"⌦",119:"↘",121:"⇟",123:"←",124:"→",125:"↓",126:"↑",50:"`",96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",109:"F10",111:"F12",118:"F4",120:"F2",122:"F1"]
        return text + (names[keyCode] ?? "Key \(keyCode)")
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

enum Palette {
    static let background = Color(nsColor: .textBackgroundColor)
    static let sidebar = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(calibratedWhite: 0.13, alpha: 1) : NSColor(calibratedRed: 246/255, green: 246/255, blue: 248/255, alpha: 1) })
    static let gold = Color(hex: 0xE8B62C)
}

/// The sidebar alone receives a small reflection from the adjacent selected row.
/// Its position is supplied by view geometry, without touching library state.
struct FloatingSidebarSurface: View {
    var selectionY: CGFloat?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        ZStack {
            if reduceTransparency { Palette.sidebar }
            else {
                shape.fill(.regularMaterial)
                Palette.sidebar.opacity(scheme == .dark ? 0.35 : 0.50)
                if let selectionY {
                    RadialGradient(colors: [ColorToken.blue.color.opacity(scheme == .dark ? 0.23 : 0.14), ColorToken.blue.color.opacity(0.045), .clear],
                                   center: UnitPoint(x: 1.10, y: selectionY), startRadius: 0, endRadius: 170)
                }
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(scheme == .dark ? 0.12 : 0.065), lineWidth: 0.5))
        .overlay(shape.strokeBorder(.white.opacity(scheme == .dark ? 0.08 : 0.55), lineWidth: 0.5)
            .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)))
        .shadow(color: .black.opacity(scheme == .dark ? 0.12 : 0.055), radius: 6, x: 0, y: 2)
        .allowsHitTesting(false)
    }
}

struct SelectedPromptRowBounds: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() { value = next }
    }
}
