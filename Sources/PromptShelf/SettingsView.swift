import SwiftUI
import PromptCore
import PromptUI

struct SettingsView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        GeometryReader { geometry in
          ScrollView {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    switch store.page {
                    case .appearance: appearanceSettings
                    case .behavior: behaviorSettings
                    case .data: dataSettings
                    case .about: aboutContent
                    case .notes: NotesSyncView(store: store, model: store.notesSync)
                    case .library: EmptyView()
                    }
                    if store.page == .appearance && geometry.size.width < 750 {
                        appearancePreview.frame(maxWidth: 400, alignment: .leading).padding(.top, 4)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if store.page == .appearance && geometry.size.width >= 750 {
                    appearancePreview.frame(width: min(360, max(260, (geometry.size.width - 48) * 0.32))).padding(.top, 3)
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
          }.background(ThinScrollbars())
        }
        .onAppear { store.refreshAccessibility() }
    }

    private var appearancePreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            WarmSectionLabel("面板预览")
            PanelPreview(store: store)
            Text("主题与面板设置实时生效。")
                .font(.system(size: 12)).foregroundStyle(.tertiary).lineSpacing(5)
        }
    }

    private var appearanceSettings: some View {
        Group {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        WarmHeading("界面缩放")
                        Spacer()
                        Picker("界面缩放", selection: preference(\.uiScale)) {
                            ForEach(8...15, id: \.self) { value in
                                Text(value == 12 ? "120%（默认）" : "\(value * 10)%").tag(Double(value) / 10)
                            }
                        }.labelsHidden().frame(width: 140).accessibilityLabel("界面缩放")
                    }
                    Text("同步调整文字、图标、控件与间距，默认 120%。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack {
                        Text("调整范围：80%–150%"); Spacer()
                        Button("恢复 120%") { store.changePreferences { $0.uiScale = 1.2 } }.buttonStyle(.plain).foregroundStyle(store.accent.color)
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 13) {
                settingsHeading("面板主题", detail: "选择快捷面板的显示材质。")
                HStack(spacing: 12) {
                    themeTile(.native, title: "原生", subtitle: "系统模糊材质")
                    themeTile(.liquidGlass, title: "Liquid Glass", subtitle: "透明玻璃材质")
                }
                if #unavailable(macOS 26) {
                    Text("Liquid Glass 在 macOS 26 上使用系统玻璃材质；当前系统使用原生模糊材质。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                }
            }
            SurfaceCard {
                VStack(alignment: .leading, spacing: 19) {
                    settingRow("显示模式", subtitle: "默认跟随系统的浅色与深色外观。") {
                        Picker("显示模式", selection: preference(\.appearance)) {
                            Text("跟随系统").tag(AppearanceMode.system)
                            Text("浅色").tag(AppearanceMode.light)
                            Text("深色").tag(AppearanceMode.dark)
                        }.labelsHidden().frame(width: 112)
                    }
                    Divider().opacity(0.6)
                    VStack(alignment: .leading, spacing: 13) {
                        WarmHeading("强调色")
                        HStack(spacing: 13) {
                            ForEach(ColorToken.allCases, id: \.rawValue) { token in
                                Button { store.changePreferences { $0.accent = token.rawValue } } label: {
                                    Circle().fill(token.color).frame(width: 23, height: 23)
                                        .overlay { if store.preferences.accent == token.rawValue { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white) } }
                                        .padding(3).overlay(Circle().strokeBorder(store.preferences.accent == token.rawValue ? token.color.opacity(0.4) : .clear, lineWidth: 1))
                                }.buttonStyle(.plain).help(token.title).accessibilityLabel(token.title)
                            }
                        }
                    }
                }
            }
            SurfaceCard {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("面板基础字号"); Spacer(); Text("\(Int(store.preferences.fontSize)) pt").foregroundStyle(.secondary).monospacedDigit() }.font(.system(size: 14))
                        Slider(value: preference(\.fontSize), in: 11...19, step: 1).accessibilityLabel("面板字号")
                    }
                    Divider().opacity(0.6)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("面板基础宽度"); Spacer(); Text("\(Int(store.preferences.panelWidth)) pt").foregroundStyle(.secondary).monospacedDigit() }.font(.system(size: 14))
                        Slider(value: preference(\.panelWidth), in: 440...680, step: 20).accessibilityLabel("面板宽度")
                    }
                }
            }
            HStack {
                Text("设置自动保存").font(.system(size: 12)).foregroundStyle(.tertiary)
                Spacer()
                Button("恢复默认外观") {
                    store.changePreferences { prefs in
                        let hotkey = prefs.hotkey; prefs = Preferences(); prefs.hotkey = hotkey
                    }
                }.font(.system(size: 13)).buttonStyle(.plain).foregroundStyle(store.accent.color)
            }
        }
    }

    private var behaviorSettings: some View {
        Group {
            settingsHeading("唤起", detail: "配置全局快捷键与跨应用填入。")
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                  HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        WarmHeading("全局快捷键")
                        Text("点击录制并按下组合键。")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HotkeyRecorder(hotkey: store.preferences.hotkey, recordingChanged: { store.recordingHotkey?($0) }, onChange: { store.setHotkey($0) }).frame(width: 200, height: 32)
                  }
                  Divider().opacity(0.5)
                  HStack {
                    Text("⌃ Control、⌥ Option、⌘ Command 至少选一，可搭配 ⇧ Shift。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("恢复默认") { store.setHotkey(Hotkey()) }.disabled(store.preferences.hotkey == Hotkey())
                  }
                  Text("支持字母、数字、符号、方向键与 F1–F12。Esc 取消；若被占用会保留原快捷键。")
                    .font(.system(size: 12)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            SurfaceCard {
                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        CategoryIcon(symbol: "hand.raised", color: store.accessibilityAllowed ? ColorToken.green.color : ColorToken.orange.color, size: 34)
                        VStack(alignment: .leading, spacing: 5) {
                            WarmHeading("辅助功能权限")
                            Text(store.accessibilityAllowed ? "已开启，可向其他应用填入文字。" : "开启后，词屿才能将提示词填回聊天框。")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button(store.accessibilityAllowed ? "打开系统设置" : "前往开启") { store.requestAccessibility() }.buttonStyle(.borderedProminent)
                        Button("重新检查") { store.refreshAccessibility() }.buttonStyle(.bordered)
                    }.controlSize(.regular)
                    Text("只用于恢复输入位置与执行粘贴。不会读取或上传聊天记录。")
                        .font(.system(size: 12)).foregroundStyle(.tertiary).lineSpacing(4)
                }
            }
            settingsHeading("填入规则", detail: "管理正文填入与文件附件。")
            SurfaceCard {
                VStack(alignment: .leading, spacing: 17) {
                    behaviorLine("cursorarrow", "恢复输入位置", "有选中文字时替换选区，否则在光标处插入。")
                    Divider().opacity(0.6)
                    behaviorLine("return", "手动发送", "正文填入后不自动发送消息。")
                    Divider().opacity(0.6)
                    behaviorLine("doc.on.clipboard", "系统剪贴板", "填入或复制正文会更新系统剪贴板。")
                    Divider().opacity(0.6)
                    behaviorLine("doc.badge.arrow.up", "Markdown 附件", "拖动关联文件的提示词到聊天框，添加 Markdown 附件。目标应用需支持文件拖放。")
                }
            }
        }
    }

    private var dataSettings: some View {
        Group {
            SurfaceCard {
              VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    CategoryIcon(symbol: "externaldrive.badge.checkmark", color: ColorToken.green.color, size: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        WarmHeading("本地资料库")
                        Text("\(store.library.prompts.count) 条提示词 · \(store.library.categories.count) 个分类").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                Text("正文与 Markdown 文件集中保存在本地资料库，自动保存并保留上一份有效备份。")
                    .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(6).padding(.top, 12)
              }
            }
            SurfaceCard {
                settingRow("导入 Markdown", subtitle: "读取正文并保存文件副本；支持从 Finder 拖入资料库或正文编辑框。") {
                    Button("选择文件…") { store.chooseMarkdownFiles() }
                }
            }
            settingsHeading("备份与迁移", detail: "导出完整资料库，或从备份合并内容。")
            SurfaceCard {
                VStack(alignment: .leading, spacing: 18) {
                    settingRow("导出提示词库", subtitle: "将正文、Markdown 文件副本和设置导出为 JSON。") { Button("导出…") { store.exportLibrary() } }
                    Divider().opacity(0.6)
                    settingRow("合并导入", subtitle: "保留现有内容，跳过重复提示词。") { Button("导入…") { store.importLibrary() } }
                }
            }
            Text("~/Library/Application Support/PromptShelf/").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            HStack(spacing: 14) {
                Button("立即保存") { Task { do { try await store.flush(); store.notify("资料库已保存") } catch { store.errorMessage = error.localizedDescription } } }
                    .disabled(store.isReadOnly)
                Text(store.storageStatus).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Button { store.revealLibrary() } label: { Label("在 Finder 中查看资料库", systemImage: "folder").font(.system(size: 14)) }.buttonStyle(.plain).foregroundStyle(store.accent.color)
        }
    }
    private var aboutContent: some View {
        Group {
            SurfaceCard {
              VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 18) {
                    BrandMark(size: 64)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("词屿 PromptShelf").font(AppTypography.title(27))
                        Text("版本 0.1.12 · macOS 原生应用").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                Text("用于管理、检索和调用提示词的 macOS 应用。")
                    .font(.system(size: 15)).lineSpacing(6).padding(.top, 18).padding(.bottom, 4)
                CreatorCredit().padding(.top, 17)
              }
            }
            SurfaceCard {
                VStack(alignment: .leading, spacing: 13) {
                    Label("本地优先，离线可用", systemImage: "externaldrive")
                    Label("原生快捷面板与键盘操作", systemImage: "keyboard")
                    Label("Markdown 文件与资料库备份", systemImage: "lock")
                }.font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Text("提示词管理 · 全局快捷调用 · Markdown 文件附件")
                .font(.system(size: 13)).foregroundStyle(.tertiary).lineSpacing(6)
        }
    }

    private func preference<T>(_ key: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { store.preferences[keyPath: key] }, set: { value in store.changePreferences { $0[keyPath: key] = value } })
    }
    private func settingsHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            WarmHeading(title)
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
    private func settingRow<Control: View>(_ title: String, subtitle: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 5)
            control()
        }
    }
    private func behaviorLine(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol).foregroundStyle(store.accent.color).frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
            }
        }
    }
    private func themeTile(_ theme: PanelTheme, title: String, subtitle: String) -> some View {
        let selected = store.preferences.theme == theme
        return Button { store.changePreferences { $0.theme = theme } } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: theme == .native ? [.gray.opacity(0.07), .gray.opacity(0.13)] : [store.accent.color.opacity(0.3), ColorToken.rose.color.opacity(0.22), .blue.opacity(0.09)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    VStack(spacing: 5) {
                        Capsule().fill(.primary.opacity(0.12)).frame(width: 62, height: 4)
                        RoundedRectangle(cornerRadius: 4).fill(store.accent.color.opacity(0.20)).frame(height: 14)
                        Capsule().fill(.primary.opacity(0.06)).frame(height: 4).padding(.trailing, 20)
                    }.padding(12).frame(width: 110).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.6), lineWidth: 1))
                }.frame(height: 83)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.system(size: 14, weight: .medium))
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? store.accent.color : .secondary.opacity(0.3)).font(.system(size: 15))
                }
            }.padding(11).frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? store.accent.color.opacity(0.65) : .primary.opacity(0.07), lineWidth: selected ? 1.5 : 1))
        }.buttonStyle(.plain)
    }
}


/// A visible native button owns focus; a window-local monitor also captures menu equivalents.
private struct HotkeyRecorder: NSViewRepresentable {
    var hotkey: Hotkey
    var recordingChanged: (Bool) -> Void
    var onChange: (Hotkey) -> Void
    func makeNSView(context: Context) -> RecorderButton { RecorderButton() }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.key = hotkey; button.recordingChanged = recordingChanged; button.changed = onChange
        if !button.recording { button.title = hotkey.display + "  ·  录制" }
    }
    static func dismantleNSView(_ button: RecorderButton, coordinator: ()) { button.finish() }

    final class RecorderButton: NSButton {
        var key = Hotkey()
        var recordingChanged: ((Bool) -> Void)?
        var changed: ((Hotkey) -> Void)?
        var recording = false
        private var monitor: Any?
        private var resignObserver: NSObjectProtocol?
        override var intrinsicContentSize: NSSize { NSSize(width: 176, height: 32) }
        override init(frame: NSRect) {
            super.init(frame: frame)
            bezelStyle = .rounded; font = .monospacedSystemFont(ofSize: 14, weight: .medium)
            target = self; action = #selector(toggleRecording)
            setAccessibilityLabel("录制全局快捷键")
            toolTip = "点击后按下组合键；Esc 取消录制"
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        @objc private func toggleRecording() {
            if recording { finish(); return }
            recording = true; title = "按下组合键 · Esc 取消"; recordingChanged?(true)
            window?.makeFirstResponder(self)
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                guard let self, self.recording, event.window === self.window else { return event }
                if event.type == .flagsChanged { return event }
                self.capture(event); return nil
            }
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            }
        }
        private func capture(_ event: NSEvent) {
            if event.keyCode == 53 { finish(); return }
            guard !event.isARepeat else { return }
            let flags = event.modifierFlags
            let modifiers: UInt32 = (flags.contains(.command) ? 256 : 0) | (flags.contains(.shift) ? 512 : 0) | (flags.contains(.option) ? 2048 : 0) | (flags.contains(.control) ? 4096 : 0)
            let candidate = Hotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            guard candidate.isValid else {
                title = candidate.isReserved ? "编辑常用键 · 换一组" : "请加入 ⌃ / ⌥ / ⌘"
                NSAccessibility.post(element: self, notification: .valueChanged)
                return
            }
            finish(); changed?(candidate)
        }
        func finish() {
            guard recording else { return }
            recording = false
            if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }; resignObserver = nil
            title = key.display + "  ·  录制"; recordingChanged?(false)
        }
        override func keyDown(with event: NSEvent) { if recording { capture(event) } else { super.keyDown(with: event) } }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if recording { capture(event); return true }; return super.performKeyEquivalent(with: event)
        }
    }
}
