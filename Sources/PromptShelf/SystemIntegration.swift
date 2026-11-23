import AppKit
import ApplicationServices
import Carbon
import Combine
import SwiftUI
import PromptCore
import PromptUI

@MainActor
final class GlobalHotkey {
    private var hotkeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var current: Hotkey?
    private var sequence: UInt32 = 0
    var action: (() -> Void)?
    private var recording = false

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { if !owner.recording { owner.action?() } }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ key: Hotkey) -> Bool {
        guard key.isValid else { return false }
        if current == key, hotkeyRef != nil { return true }
        sequence &+= 1
        var newRef: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x50534846), id: sequence)
        let result = RegisterEventHotKey(key.keyCode, key.modifiers, id, GetApplicationEventTarget(), 0, &newRef)
        guard result == noErr, let newRef else { return false }
        if let old = hotkeyRef { UnregisterEventHotKey(old) }
        hotkeyRef = newRef; current = key
        return true
    }
    func setRecording(_ active: Bool) {
        guard recording != active else { return }
        recording = active
        if active {
            if let hotkeyRef { UnregisterEventHotKey(hotkeyRef) }; hotkeyRef = nil
        } else if let current { _ = register(current) }
    }
    func stop() {
        if let hotkeyRef { UnregisterEventHotKey(hotkeyRef) }; hotkeyRef = nil
        if let handler { RemoveEventHandler(handler) }; handler = nil
    }
}

struct InputTarget {
    let app: NSRunningApplication
    let element: AXUIElement?
    let selection: CFTypeRef?
    var name: String { app.localizedName ?? "目标应用" }
}

@MainActor
enum InputBridge {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    static func focusedElement(_ app: NSRunningApplication) -> AXUIElement? {
        guard let value = attribute(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func editable(_ element: AXUIElement) -> Bool {
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
        if subrole == kAXSecureTextFieldSubrole as String { return false }
        if let enabled = attribute(element, kAXEnabledAttribute) as? Bool, !enabled { return false }
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success, settable.boolValue { return true }
        return [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String].contains(role)
    }
    static func capture() -> InputTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let element = AXIsProcessTrusted() ? focusedElement(app) : nil
        return InputTarget(app: app, element: element, selection: element.flatMap { attribute($0, kAXSelectedTextRangeAttribute) })
    }
    static func preflight(_ target: InputTarget?) -> String? {
        guard AXIsProcessTrusted() else { return "正文填入需要辅助功能权限。可使用「复制」或拖动 Markdown 附件。" }
        guard let target, !target.app.isTerminated else { return "请先点击目标聊天输入框，再用快捷键唤起。当前可以使用「复制」。" }
        guard let element = target.element, editable(element) else { return "未能确认可编辑的输入位置。请先点击聊天框后重试，或使用「复制」。" }
        return nil
    }
    /// Never reads the target's text. Verify app + focused element before posting a targeted paste.
    static func paste(_ text: String, into target: InputTarget) async -> String? {
        await paste(.text(text), into: target)
    }
    static func paste(_ payload: PromptPastePayload, into target: InputTarget) async -> String? {
        guard AXIsProcessTrusted(), let element = target.element, !target.app.isTerminated else { return "权限或目标输入位置已失效，请重新唤起后重试。" }
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return "无法创建粘贴操作，请使用「复制」。" }
        target.app.activate(options: [])
        for _ in 0..<24 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.app.processIdentifier { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.app.processIdentifier else { return "未能回到原应用，已停止填入。可以复制后手动粘贴。" }
        // A non-activating panel normally preserves this focus. Restore only the recorded element.
        if let current = focusedElement(target.app), !CFEqual(current, element) {
            _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard let focused = focusedElement(target.app), CFEqual(focused, element), editable(focused) else {
            return "输入焦点已改变，已停止填入。请回到聊天框重新唤起，或复制后手动粘贴。"
        }
        if let selection = target.selection {
            _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, selection)
        }
        // Releasing the trigger modifiers avoids carrying Control/Option into Command-V.
        for _ in 0..<40 {
            if NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            return "请松开快捷键后重试。当前没有执行粘贴。"
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.app.processIdentifier,
              let finalFocus = focusedElement(target.app), CFEqual(finalFocus, element) else {
            return "输入焦点已改变，请重新唤起后重试。"
        }
        guard payload.write(to: .general) else { return "无法准备粘贴内容，请重新唤起后重试。" }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.postToPid(target.app.processIdentifier)
        try? await Task.sleep(for: .milliseconds(15))
        up.postToPid(target.app.processIdentifier)
        return nil
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickPanelController: NSObject, NSWindowDelegate {
    let store: AppStore
    private(set) var panel: FloatingPanel?
    private var model: PanelModel?
    private var target: InputTarget?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var insertionTask: Task<Void, Never>?
    var showSettings: (() -> Void)?

    init(store: AppStore) { self.store = store }
    func toggle() { if panel?.isVisible == true { hide() } else { show() } }
    func show() {
        guard insertionTask == nil else { return }
        hide()
        target = InputBridge.capture()
        store.refreshAccessibility()
        let model = PanelModel(store: store); self.model = model
        model.targetName = target?.name ?? ""
        if !store.accessibilityAllowed { model.notice = "正文填入需要辅助功能权限。复制正文与拖动 Markdown 附件不受影响。" }
        model.cancel = { [weak self] in self?.hide() }
        model.fileDragStarted = { [weak self] in self?.removeMouseMonitors() }
        model.fileDragEnded = { [weak self] id, accepted in
            guard let self else { return }
            if accepted { self.store.markUsed(id); self.hide() }
            else {
                // Reopen a cancelled session with a fresh input target and outside-click monitors.
                self.hide(); self.show()
            }
        }
        model.openSettings = { [weak self] in self?.hide(); self?.showSettings?() }
        model.insert = { [weak self] prompt in self?.insert(prompt) }
        model.insertText = { [weak self] text, id in self?.performInsert(.text(text), sourceID: id) }
        model.insertFiles = { [weak self, weak model] prompt in
            guard let self, let model else { return }
            do { self.performInsert(.files(try model.markdownFiles(for: prompt)), sourceID: prompt.id) }
            catch { model.notice = "Markdown 文件生成失败：\(error.localizedDescription)" }
        }
        model.contextMenuChanged = { [weak self, weak model] open in
            guard let self, let model else { return }
            model.isShowingContextMenu = open
            if open { self.removeMouseMonitors() }
            else {
                DispatchQueue.main.async { [weak self, weak model] in
                    guard let self, let model, self.model === model, self.panel?.isVisible == true else { return }
                    self.installMouseMonitors()
                }
            }
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(store.preferences.panelWidth * store.preferences.uiScale, bounds.width - 24),
                          height: min(model.contentHeight * store.preferences.uiScale, bounds.height - 24))
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "词屿 · 快捷面板"
        panel.isFloatingPanel = true; panel.level = .floating
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.appearance = store.appearance
        let hostingView = NSHostingView(rootView: QuickPanelView(store: store, model: model))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hostingView
        panel.delegate = self
        let x = min(max(mouse.x - 70, bounds.minX + 12), bounds.maxX - size.width - 12)
        let y = min(max(mouse.y - size.height - 18, bounds.minY + 12), bounds.maxY - size.height - 12)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        self.panel = panel
        model.sizeChanged = { [weak self] in self?.resizePanel() }
        panel.makeKeyAndOrderFront(nil)
        installMouseMonitors()
    }
    private func installMouseMonitors() {
        removeMouseMonitors()
        guard let panel, panel.isVisible, model?.isShowingContextMenu != true else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.hide() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            if event.window !== panel { self?.hide() }; return event
        }
    }
    func hide() {
        panel?.orderOut(nil)
        removeMouseMonitors()
    }
    private func removeMouseMonitors() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }; globalMouseMonitor = nil
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }; localMouseMonitor = nil
    }
    func windowDidResignKey(_ notification: Notification) {
        if insertionTask == nil && model?.isDraggingFile != true && model?.isShowingContextMenu != true { hide() }
    }
    private func insert(_ prompt: Prompt) {
        performInsert(.text(prompt.body), sourceID: prompt.id)
    }
    private func performInsert(_ payload: PromptPastePayload, sourceID: UUID) {
        guard let model, !model.isInserting else { return }
        if let error = InputBridge.preflight(target) {
            model.notice = error
            if case .files = payload, payload.write(to: .general) { model.notice = error + " 文件已复制，可返回聊天框粘贴，或拖动提示词添加文件。" }
            return
        }
        guard let target else { return }
        model.isInserting = true
        // Remove outside-click monitors before returning focus to the external app.
        hide()
        insertionTask = Task { [weak self] in
            let error = await InputBridge.paste(payload, into: target)
            guard let self else { return }
            self.insertionTask = nil; model.isInserting = false
            if let error {
                model.notice = error; self.panel?.makeKeyAndOrderFront(nil)
                self.installMouseMonitors()
            } else { self.store.markUsed(sourceID) }
        }
    }
    private func resizePanel() {
        guard let panel, let model else { return }
        let bounds = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        var rect = panel.frame
        let top = rect.maxY
        rect.size = NSSize(width: min(store.preferences.panelWidth * store.preferences.uiScale, bounds.width - 24), height: min(model.contentHeight * store.preferences.uiScale, bounds.height - 24))
        rect.origin.y = min(max(top - rect.height, bounds.minY + 12), bounds.maxY - rect.height - 12)
        rect.origin.x = min(max(rect.origin.x, bounds.minX + 12), bounds.maxX - rect.width - 12)
        panel.setFrame(rect, display: true)
    }
    func updateAppearance() {
        panel?.appearance = store.appearance
        resizePanel()
    }
}
