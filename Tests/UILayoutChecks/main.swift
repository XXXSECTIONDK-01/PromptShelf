import SwiftUI
import AppKit
import PromptCore
import PromptUI
import QuartzCore

private final class DisplayLinkProbe: NSObject {
    @objc func step(_ link: CADisplayLink) {}
}

@main struct UILayoutChecks {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard let icon = NSImage(contentsOfFile: "Resources/AppIconArtwork.png"), icon.isValid else { throw LibraryError.invalid("Missing application artwork") }
        _ = icon.setName(NSImage.Name("AppIconArtwork"))
        guard AppIdentity.icon != nil, AppIdentity.creatorTag == "MADE BY ANDY CHEN",
              AppIdentity.githubURL.absoluteString == "https://github.com/XXXSECTIONDK-01" else { throw LibraryError.invalid("Creator identity or bundled icon is incorrect") }
        for fps in [60, 120, 144, 240] {
            let range = DisplayCadence.range(maximumFramesPerSecond: fps, lowPower: false)
            guard range.maximum == Float(fps), range.preferred == Float(fps) else { throw LibraryError.invalid("Display cadence capped a supported screen") }
            let transition = DisplayTransition(from: 0, to: 1, started: 100)
            var previous: CGFloat = 0
            for frame in 0...Int(ceil(0.28 * Double(fps))) {
                let time = 100 + Double(frame) / Double(fps)
                let progress = transition.value(at: time)
                guard progress >= previous, progress <= 1 else { throw LibraryError.invalid("Frame-rate change broke animation progress") }
                previous = progress
            }
            guard abs(transition.value(at: 100.14) - 0.5) < 0.001,
                  transition.isFinished(at: 100.29), transition.value(at: 100.29) == 1,
                  (DisplayCadence.range(maximumFramesPerSecond: fps, lowPower: true).preferred ?? .infinity) <= 60 else {
                throw LibraryError.invalid("Animation duration or low-power cadence changed with refresh rate")
            }
        }
        let reverse = DisplayTransition(from: 0.6, to: 0, started: 200, duration: 0.168)
        guard reverse.value(at: 200) == 0.6, reverse.value(at: 200.2) == 0 else { throw LibraryError.invalid("Reversing hover caused a jump") }
        let idleReel = DisplaySynchronizedReel.ReelView(frame: NSRect(x: 0, y: 0, width: 150, height: 19))
        idleReel.show(chinese: false, animated: true); idleReel.show(chinese: true, animated: false)
        guard !idleReel.hasActiveDisplayLink else { throw LibraryError.invalid("An idle/detached or reduced-motion reel kept ticking") }
        print("PASS creator link and artwork, 60/120/144/240 Hz cadence, constant duration, reversal, low-power policy and idle display-link teardown")
        var streak = BrandHoverSequence()
        for entry in 1...10 {
            guard !streak.update(inside: true, now: Double(entry)),
                  !streak.update(inside: true, now: Double(entry) + 0.1),
                  !streak.update(inside: false, now: Double(entry) + 0.2) else { throw LibraryError.invalid("Brand easter egg fired before eleven entries") }
        }
        guard streak.update(inside: true, now: 11), !streak.update(inside: true, now: 11.1) else { throw LibraryError.invalid("Brand easter egg failed or repeated within one entry") }
        _ = streak.update(inside: false, now: 11.2)
        guard !streak.update(inside: true, now: 18), streak.count == 1 else { throw LibraryError.invalid("Idle hover streak did not reset") }
        let specimen = "# **章节标题**\n\n正文 **强调** 和表情 🍊。\n\n```markdown\n## 代码标题\n**代码内容**\n```\n\n## 阅读目标"
        let styled = WarmPromptText.make(specimen, fontSize: 15)
        let original = specimen as NSString
        guard styled.text.string == specimen, let first = styled.firstHeading,
              let headingFont = styled.text.attribute(.font, at: first.location, effectiveRange: nil) as? NSFont,
              headingFont.fontName.contains("Songti"),
              styled.text.attribute(.underlineStyle, at: first.location, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue,
              styled.text.attribute(.underlineStyle, at: original.range(of: "代码标题").location, effectiveRange: nil) == nil,
              (styled.text.attribute(.font, at: original.range(of: "代码内容").location, effectiveRange: nil) as? NSFont)?.fontName == NSFont.systemFont(ofSize: 15).fontName else {
            throw LibraryError.invalid("Warm typography changed source, lost Songti titles or styled fenced code")
        }
        print("PASS brand eleventh-entry threshold, duplicate-event protection, idle reset, Songti headings, warm underline, fenced code and exact source preservation")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PromptShelf-UILayout-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppStore(storageURL: root.appendingPathComponent("library.json"))
        for _ in 0..<1000 where store.isLoading { try await Task.sleep(for: .milliseconds(5)) }
        guard !store.isLoading, store.errorMessage == nil else { throw LibraryError.invalid("Startup failed") }
        let id = UUID(), long = String(repeating: "长文字布局与数据保存检查。\n", count: 1500)
        guard store.commit({ $0.prompts.append(Prompt(id: id, title: "长正文布局检查", body: long)) }) else { throw LibraryError.invalid("Commit failed") }
        try await store.flush()
        guard try LibraryFile(url: root.appendingPathComponent("library.json")).load()?.prompts.first(where: { $0.id == id })?.body == long else { throw LibraryError.invalid("Async flush lost content") }
        store.selectedID = id
        store.query = "长正文布局"
        try await Task.sleep(for: .milliseconds(250))
        guard store.visiblePrompts.map(\.id) == [id] else { throw LibraryError.invalid("Background search failed") }
        store.query = "不存在的结果"; store.query = ""
        try await Task.sleep(for: .milliseconds(150))
        guard store.visiblePrompts.count == store.library.prompts.count else { throw LibraryError.invalid("Stale search result replaced clear query") }
        print("PASS async startup, durable flush, background search and stale search cancellation")
        let host = NSHostingView(rootView: LibraryView(store: store))
        host.sizingOptions = []
        var checked = 0
        let visibleScreen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        print("Screen available: \(Int(visibleScreen.width)) × \(Int(visibleScreen.height))")
        for scale in [0.8, 1.0, 1.2, 1.5] {
            store.changePreferences { $0.uiScale = scale }
            for page in [AppPage.library, .appearance, .behavior, .data, .notes, .about] {
                store.page = page
                for base in [NSSize(width: 1040, height: 680), NSSize(width: 1440, height: 900)] {
                    let size = NSSize(width: min(base.width * scale, visibleScreen.width), height: min(base.height * scale, visibleScreen.height))
                    host.frame = NSRect(origin: .zero, size: size)
                    host.layoutSubtreeIfNeeded()
                    guard host.frame.size == size else { throw LibraryError.invalid("Window layout did not follow size") }
                    checked += 1
                }
            }
        }
        store.changePreferences { $0.uiScale = 1.2 }
        store.page = .library; store.selectedID = store.library.prompts.first?.id
        host.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua); window.contentView = host
        func snapshot(_ name: String) async throws {
            try await Task.sleep(for: .milliseconds(350)); host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds),
                  let _ = window.contentView else { throw LibraryError.invalid("Cannot capture offscreen view") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw LibraryError.invalid("Cannot encode snapshot") }
            try png.write(to: URL(fileURLWithPath: ".build/\(name).png"))
        }
        let typographyID = UUID()
        _ = store.commit { $0.prompts.append(Prompt(id: typographyID, title: "自然论述基础版_V3.5", body: "请以有阅读经验、思路清楚的中文作者口吻写作。\n\n## 角色与目标\n保留作者希望表达的**观点、事实与证据**。把零散材料组织成连贯的文字，兼顾逻辑、节奏与阅读体验。\n\n## 一、先决定要表达什么\n围绕一个明确的中心组织内容，先判断哪些信息值得展开，再安排背景与解释。\n\n## 二、让段落自然衔接\n每个段落只推进一个主要意思。使用具体的例子和清楚的动词，保留原始材料中的数字与名称。")) }
        store.selectedID = typographyID
        try await snapshot("ui-0.1.12-light")
        store.page = .about
        try await snapshot("ui-0.1.12-about")
        store.page = .appearance
        try await snapshot("ui-0.1.12-appearance")
        store.page = .library
        store.changePreferences { $0.uiScale = 1.5 }
        try await snapshot("ui-0.1.12-150")
        store.changePreferences { $0.uiScale = 1.0 }
        try await snapshot("ui-0.1.12-100")
        store.changePreferences { $0.uiScale = 1.2 }
        let topSelection = store.selectedID
        store.selectedID = store.visiblePrompts.dropFirst(4).first?.id
        try await snapshot("ui-0.1.12-selection-lower")
        window.appearance = NSAppearance(named: .darkAqua)
        host.rootView = LibraryView(store: store)
        try await snapshot("ui-0.1.12-dark")
        window.appearance = NSAppearance(named: .aqua)
        store.selectedID = topSelection
        func nativeViews<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { nativeViews($0, type) }
        }
        store.selectedID = id
        try await Task.sleep(for: .milliseconds(200)); host.layoutSubtreeIfNeeded()
        if let reel = nativeViews(host, DisplaySynchronizedReel.ReelView.self).first {
            let detachedLink = reel.displayLink(target: DisplayLinkProbe(), selector: #selector(DisplayLinkProbe.step(_:)))
            detachedLink.preferredFrameRateRange = DisplayCadence.range(maximumFramesPerSecond: window.screen?.maximumFramesPerSecond ?? 0, lowPower: false)
            // Never register a link for hidden test windows: verify the AppKit API and configuration, not physical FPS.
            detachedLink.invalidate()
            guard !reel.hasActiveDisplayLink else { throw LibraryError.invalid("Offscreen brand kept an animation loop active") }
        } else { throw LibraryError.invalid("Missing display-synchronized brand view") }
        let scrolls = nativeViews(host, NSScrollView.self)
        guard scrolls.count >= 3 else { throw LibraryError.invalid("Missing sidebar, list or reader scroll view") }
        for scroll in scrolls {
            guard scroll.scrollerStyle == .overlay,
                  scroll.verticalScroller == nil || scroll.verticalScroller is ThinScroller,
                  scroll.horizontalScroller == nil || scroll.horizontalScroller is ThinScroller else {
                throw LibraryError.invalid("A window scroll view retained a legacy or thick scroller")
            }
        }
        guard let reader = scrolls.first(where: { ($0.documentView as? NSTextView)?.string == long }),
              let text = reader.documentView as? NSTextView else { throw LibraryError.invalid("Missing long text preview") }
        text.scrollRangeToVisible(NSRange(location: (long as NSString).length - 1, length: 1))
        guard reader.contentView.bounds.minY > 0 else { throw LibraryError.invalid("Thin scrollbars broke long-document scrolling") }
        let thumb = ThinScroller(frame: NSRect(x: 0, y: 0, width: 12, height: 300))
        let thumbWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 350), styleMask: [.borderless], backing: .buffered, defer: false)
        let thumbRoot = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 350))
        thumbWindow.contentView = thumbRoot; thumbRoot.addSubview(thumb)
        thumb.scrollerStyle = .overlay; thumb.isEnabled = true; thumb.knobProportion = 0.2; thumb.doubleValue = 0.4
        let painted = thumb.paintedKnobRect, hit = thumb.rect(for: .knob)
        guard painted.width == 3, painted.height > 0, hit.width > painted.width else {
            throw LibraryError.invalid("Thumb should paint 3pt while retaining its native interaction width")
        }
        // AppKit, rather than a custom mouse handler, still identifies the thumb.
        guard thumb.testPart(thumb.convert(NSPoint(x: hit.midX, y: hit.midY), to: nil)) == .knob else { throw LibraryError.invalid("Native thumb hit testing failed") }
        for token in ColorToken.allCases {
            let normal = NSColor(ColorToken.categoryLabel(token.rawValue, selected: false)).usingColorSpace(.deviceRGB)!
            let original = NSColor(token.color).usingColorSpace(.deviceRGB)!
            guard abs(normal.redComponent - original.redComponent) < 0.001,
                  abs(normal.greenComponent - original.greenComponent) < 0.001,
                  abs(normal.blueComponent - original.blueComponent) < 0.001 else { throw LibraryError.invalid("Category lost its saved color") }
            if token != .gray {
                let selected = NSColor(ColorToken.categoryLabel(token.rawValue, selected: true)).usingColorSpace(.deviceRGB)!
                guard max(selected.redComponent, selected.greenComponent, selected.blueComponent) - min(selected.redComponent, selected.greenComponent, selected.blueComponent) > 0.03 else {
                    throw LibraryError.invalid("Selected category became monochrome")
                }
            }
        }
        try await snapshot("ui-0.1.12-long-text")
        store.selectedID = topSelection
        print("PASS thin overlay scrollbars across \(scrolls.count) native scroll views, long-text scrolling, native thumb target and six category colors")
        for scale in [1.0, 0.8, 1.2, 1.5] {
            store.changePreferences { $0.uiScale = scale }
            try await Task.sleep(for: .milliseconds(200)); host.layoutSubtreeIfNeeded()
            for view in nativeViews(host, NSSearchField.self) {
                let rect = view.bounds
                let point = view.convert(NSPoint(x: rect.midX, y: rect.midY), to: host.superview)
                guard let hit = host.hitTest(point), hit === view || hit.isDescendant(of: view) else {
                    throw LibraryError.invalid("Scaled search field hit target is incorrect at \(scale)")
                }
            }
        }
        for page in [AppPage.library, .appearance, .behavior, .data, .notes, .about] {
            store.page = page
            try await Task.sleep(for: .milliseconds(120)); host.layoutSubtreeIfNeeded()
            let created = nativeViews(host, NSScrollView.self)
            guard !created.isEmpty, created.allSatisfy({ $0.scrollerStyle == .overlay && ($0.verticalScroller == nil || $0.verticalScroller is ThinScroller) }) else {
                throw LibraryError.invalid("Page \(page) transition created an unstyled scroll view (count: \(created.count))")
            }
        }
        store.page = .library
        try await Task.sleep(for: .milliseconds(120)); host.layoutSubtreeIfNeeded()
        let legacy = nativeViews(host, NSScrollView.self)
        legacy.forEach { $0.scrollerStyle = .legacy }
        NotificationCenter.default.post(name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(120))
        guard legacy.allSatisfy({ $0.scrollerStyle == .overlay }) else { throw LibraryError.invalid("System-style notification restored thick legacy bars") }
        print("PASS new scroll views on all six pages and restoration after a local legacy-style notification")
        store.changePreferences { $0.uiScale = 1.2 }
        let panelModel = PanelModel(store: store)
        panelModel.targetName = "测试输入框"
        let panelHost = NSHostingView(rootView: QuickPanelView(store: store, model: panelModel))
        panelHost.sizingOptions = []
        panelHost.frame = NSRect(x: 0, y: 0, width: store.preferences.panelWidth * 1.2, height: panelModel.contentHeight * 1.2)
        let panelWindow = NSWindow(contentRect: panelHost.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panelWindow.appearance = NSAppearance(named: .aqua); panelWindow.contentView = panelHost
        try await Task.sleep(for: .milliseconds(150)); panelHost.layoutSubtreeIfNeeded()
        if let bitmap = panelHost.bitmapImageRepForCachingDisplay(in: panelHost.bounds) {
            panelHost.cacheDisplay(in: panelHost.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ".build/ui-0.1.12-panel.png"))
        }
        let draft = PromptDraft(prompt: store.library.prompts[0], isNew: false)
        let editorHost = NSHostingView(rootView: ScaledPromptSheet(scale: 1.2) { height in PromptEditor(store: store, initial: draft, height: height) }.background(Color(nsColor: .windowBackgroundColor)))
        editorHost.frame = NSRect(origin: .zero, size: editorHost.fittingSize)
        let editorWindow = NSWindow(contentRect: editorHost.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        editorWindow.appearance = NSAppearance(named: .aqua); editorWindow.contentView = editorHost
        try await Task.sleep(for: .milliseconds(150)); editorHost.layoutSubtreeIfNeeded()
        if let bitmap = editorHost.bitmapImageRepForCachingDisplay(in: editorHost.bounds) {
            editorHost.cacheDisplay(in: editorHost.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ".build/ui-0.1.12-editor.png"))
        }
        guard editorHost.frame.height <= visibleScreen.height - 99 else { throw LibraryError.invalid("Scaled editor exceeds the visible display") }
        for (name, chinese, egg) in [("english", false, false), ("chinese", true, false), ("egg", true, true)] {
            let brand = NSHostingView(rootView: BrandWordmarkLabel(chinese: chinese, showEasterEgg: egg).frame(width: 150, height: 19).padding(25).frame(width: 220, height: 125, alignment: .topLeading).background(Palette.sidebar))
            brand.frame = NSRect(x: 0, y: 0, width: 220, height: 125)
            let brandWindow = NSWindow(contentRect: brand.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            brandWindow.appearance = NSAppearance(named: .aqua); brandWindow.contentView = brand
            try await Task.sleep(for: .milliseconds(80)); brand.layoutSubtreeIfNeeded()
            if let bitmap = brand.bitmapImageRepForCachingDisplay(in: brand.bounds) {
                brand.cacheDisplay(in: brand.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: ".build/ui-0.1.12-brand-\(name).png"))
            }
        }
        print("PASS scaled native search hit targets, quick panel and editor sizing")
        let box100 = NSHostingView(rootView: Color.blue.frame(width: 100, height: 40).modifier(InterfaceScale(scale: 1.0)))
        let box120 = NSHostingView(rootView: Color.blue.frame(width: 100, height: 40).modifier(InterfaceScale(scale: 1.2)))
        guard abs(box120.fittingSize.width - box100.fittingSize.width * 1.2) < 0.5,
              abs(box120.fittingSize.height - box100.fittingSize.height * 1.2) < 0.5 else { throw LibraryError.invalid("Scaled layout did not reserve 120% space") }
        try await store.flush()
        guard try LibraryFile(url: root.appendingPathComponent("library.json")).load()?.preferences.uiScale == 1.2 else { throw LibraryError.invalid("UI scale was not persisted") }
        print("PASS 120% layout measurement and preference persistence")
        print("PASS offscreen light, dark and moved-selection snapshots")
        print("PASS \(checked) page/size layout checks; no windows presented, no accessibility prompts or Notes access")
    }
}
