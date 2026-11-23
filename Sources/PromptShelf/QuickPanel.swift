import SwiftUI
import Combine
import PromptCore
import PromptUI

@MainActor
final class PanelModel: ObservableObject {
    @Published var query = "" { didSet { refreshResults() } }
    @Published var filter: LibraryFilter = .all { didSet { refreshResults() } }
    @Published var selectedID: UUID?
    @Published var notice: String?
    @Published var showPreview = false
    @Published var isInserting = false
    @Published var draft: InstantDraft?
    var sizeChanged: (() -> Void)?
    var fileDragStarted: (() -> Void)?
    var fileDragEnded: ((UUID, Bool) -> Void)?
    var isDraggingFile = false
    var isShowingContextMenu = false
    var contextMenuChanged: ((Bool) -> Void)?
    var rowHeight: Double { store.preferences.fontSize * 2 + 32 }
    var contentHeight: Double {
        if draft != nil { return 450 + (notice == nil ? 0 : 64) }
        return 54 + 42 + 12 + (prompts.isEmpty ? 126 : Double(min(prompts.count, 4)) * rowHeight)
            + 38 + (showPreview && selected != nil ? 226 : 0) + (notice == nil ? 0 : 64)
    }
    var targetName = ""
    var insert: ((Prompt) -> Void)?
    var insertText: ((String, UUID) -> Void)?
    var insertFiles: ((Prompt) -> Void)?
    var cancel: (() -> Void)?
    var openSettings: (() -> Void)?
    let store: AppStore
    @Published private(set) var prompts: [Prompt] = []
    private var searchTask: Task<Void, Never>?
    private var subscription: AnyCancellable?
    init(store: AppStore) {
        self.store = store
        subscription = store.$revision.sink { [weak self] _ in self?.refreshResults() }
    }
    func refreshResults() {
        searchTask?.cancel()
        let snapshot = store.library, filter = filter, query = query
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompts = snapshot.filtered(filter)
            if !prompts.contains(where: { $0.id == selectedID }) { resetSelection() }
            sizeChanged?()
        } else {
            searchTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                let results = await Task.detached(priority: .userInitiated) { snapshot.filtered(filter, query: query) }.value
                guard !Task.isCancelled, let self else { return }
                self.prompts = results; self.resetSelection(); self.sizeChanged?()
            }
        }
    }
    var selected: Prompt? { prompts.first { $0.id == selectedID } }
    func resetSelection() { selectedID = prompts.first?.id }
    func move(_ direction: Int) {
        guard !prompts.isEmpty else { return }
        let index = prompts.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(index + direction, 0), prompts.count - 1)
        selectedID = prompts[next].id
    }
    func handle(_ command: String) -> Bool {
        switch command {
        case "moveDown:": move(1); return true
        case "moveUp:": move(-1); return true
        case "insertNewline:": useSelected(); return true
        case "cancelOperation:": cancel?(); return true
        default: return false
        }
    }
    func useSelected() { guard !isInserting, let selected else { return }; insert?(selected) }
    func beginInstantEdit(_ prompt: Prompt) {
        guard !isInserting else { return }
        selectedID = prompt.id; notice = nil; draft = InstantDraft(prompt: prompt)
    }
    func discardDraft() { draft = nil; notice = nil }
    func completeDraft() {
        guard !isInserting, let draft else { return }
        do { insertText?(try draft.validatedBody(), draft.sourceID) }
        catch { notice = error.localizedDescription }
    }
    func markdownFiles(for prompt: Prompt) throws -> [URL] {
        try InstantOutput.materialize(InstantOutput.markdownDocuments(for: prompt), in: FileManager.default.temporaryDirectory.appendingPathComponent("PromptShelf-OneShot", isDirectory: true))
    }
}

struct QuickPanelView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var model: PanelModel
    var body: some View {
        Group {
            if model.draft != nil {
                InstantEditorView(store: store, model: model)
                    .modifier(PanelSurface(theme: store.preferences.theme)).tint(store.accent.color)
            } else { candidateContent }
        }
        .modifier(InterfaceScale(scale: store.preferences.uiScale))
        .onChange(of: model.draft?.sourceID) { _, _ in model.sizeChanged?() }
        .onChange(of: model.notice) { _, _ in model.sizeChanged?() }
        .onExitCommand { if model.draft != nil { model.discardDraft() } else { model.cancel?() } }
    }
    private var candidateContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                NativeSearch(text: $model.query, placeholder: "搜索提示词", focus: true, command: model.handle)
                    .frame(height: 28)
                IconButton(symbol: model.showPreview ? "eye.fill" : "eye", help: model.showPreview ? "关闭内容预览" : "打开内容预览") { model.showPreview.toggle() }
                    .background(model.showPreview ? store.accent.color.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                Button { model.cancel?() } label: { Keycap(text: "esc") }.buttonStyle(.plain).help("关闭面板")
            }.padding(.horizontal, 14).frame(height: 54)
            Divider().opacity(0.35)
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    chip("全部", filter: .all)
                    chip("收藏", filter: .favorites)
                    chip("最近", filter: .recent)
                    ForEach(store.library.categories) { category in chip(category.name, filter: .category(category.id)) }
                }.padding(.horizontal, 12).frame(height: 42)
            }.scrollIndicators(.hidden).background(ThinScrollbars())
            Divider().opacity(0.45)
            if model.prompts.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "没有匹配的提示词", detail: "调整关键词或切换分类。")
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.prompts) { prompt in
                                quickRow(prompt).id(prompt.id)
                            }
                        }.padding(.horizontal, 8).padding(.vertical, 6)
                    }.scrollIndicators(.hidden).background(ThinScrollbars())
                        .onChange(of: model.selectedID) { _, id in if let id { reader.scrollTo(id, anchor: .center) } }
                        .onChange(of: model.query) { _, _ in reader.scrollTo(model.selectedID, anchor: .top) }
                }
            }
            if model.showPreview, let selected = model.selected {
                PromptPreviewCard(prompt: selected, category: store.library.category(for: selected)?.name ?? "通用", accent: store.accent.color, fontSize: store.preferences.fontSize) {
                    model.showPreview = false
                }.frame(height: 210).padding(8)
            }
            if let notice = model.notice {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").padding(.top, 1)
                    Text(notice).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if !store.accessibilityAllowed { Button("设置") { model.openSettings?() }.buttonStyle(.plain).foregroundStyle(store.accent.color) }
                }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 14).frame(height: 64)
                    .background(store.accent.color.opacity(0.06))
            }
            Divider().opacity(0.45)
            HStack(spacing: 7) {
                Image(systemName: model.targetName.isEmpty ? "text.cursor" : "arrow.turn.down.left")
                Text(model.targetName.isEmpty ? "未选择输入框" : "填入 \(model.targetName)")
                    .lineLimit(1)
                Spacer(minLength: 3)
                if model.isInserting { ProgressView().controlSize(.mini) }
                else {
                    Keycap(text: "↑↓")
                    Text("选择").foregroundStyle(.tertiary)
                    Keycap(text: "↵")
                    Text("填入").foregroundStyle(.tertiary)
                    Button("复制") {
                        guard let prompt = model.selected else { return }
                        store.copy(prompt); model.notice = "已复制，可以回到聊天框手动粘贴。"
                    }.buttonStyle(.plain).foregroundStyle(store.accent.color).disabled(model.selected == nil)
                }
            }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 14).frame(height: 38)
        }
        .modifier(PanelSurface(theme: store.preferences.theme))
        .tint(store.accent.color)
        .onChange(of: model.query) { _, _ in model.resetSelection(); model.sizeChanged?() }
        .onChange(of: model.filter) { _, _ in model.resetSelection(); model.sizeChanged?() }
        .onChange(of: model.showPreview) { _, _ in model.sizeChanged?() }
        .onChange(of: store.revision) { _, _ in
            model.sizeChanged?()
            if !model.prompts.contains(where: { $0.id == model.selectedID }) { model.resetSelection() }
        }
    }

    private func chip(_ title: String, filter: LibraryFilter) -> some View {
        let selected = model.filter == filter
        return Button { model.filter = filter } label: {
            Text(title).font(.system(size: 12, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? store.accent.color : .secondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? store.accent.color.opacity(0.15) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).focusable(false)
    }
    private func quickRow(_ prompt: Prompt) -> some View {
            MarkdownDragRow(label: "\(prompt.title)，右键即时编辑或输出 Markdown 文件", prepareFiles: {
                do { return try model.markdownFiles(for: prompt) }
                catch { model.notice = "文件读取失败：\(error.localizedDescription)"; return nil }
            }, click: {
                model.selectedID = prompt.id; model.useSelected()
            }, started: {
                model.selectedID = prompt.id; model.isDraggingFile = true; model.fileDragStarted?()
            }, ended: { accepted in
                model.isDraggingFile = false; model.fileDragEnded?(prompt.id, accepted)
            }, actions: [
                PromptRowAction("即时编辑…", symbol: "square.and.pencil") { model.beginInstantEdit(prompt) },
                PromptRowAction("以 Markdown 文件输出", symbol: "doc.badge.arrow.up") {
                    guard !model.isInserting else { return }
                    model.selectedID = prompt.id; model.insertFiles?(prompt)
                }
            ], menuChanged: { open in
                if open { model.selectedID = prompt.id }
                model.contextMenuChanged?(open)
            }) { quickRowLabel(prompt) }
                .frame(height: model.rowHeight).frame(maxWidth: .infinity)
                .accessibilityAddTraits(prompt.id == model.selectedID ? .isSelected : [])
    }
    private func quickRowLabel(_ prompt: Prompt) -> some View {
        let selected = prompt.id == model.selectedID
        let category = store.library.category(for: prompt)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(prompt.title).font(AppTypography.title(store.preferences.fontSize)).lineLimit(1)
                    if prompt.markdown != nil {
                        Text("MD").font(.system(size: 9, weight: .semibold)).foregroundStyle(store.accent.color)
                            .padding(.horizontal, 4).padding(.vertical, 2).background(store.accent.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 3))
                    }
                    if prompt.isFavorite { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Palette.gold) }
                    Spacer(minLength: 0)
                }
                Text(prompt.excerpt).font(.system(size: store.preferences.fontSize - 2)).foregroundStyle(.secondary).lineLimit(1)
            }
            VStack(alignment: .trailing, spacing: 5) {
                Text(category?.name ?? "通用").lineLimit(1)
                if prompt.markdown != nil { Label("拖动附件", systemImage: "paperclip").font(.system(size: 10)) }
            }.font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: 70, alignment: .trailing)
        }.padding(.horizontal, 12).frame(height: model.rowHeight).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? store.accent.color.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) {
                if selected { RoundedRectangle(cornerRadius: 2).fill(store.accent.color).frame(width: 2.5).padding(.vertical, 10) }
            }.contentShape(Rectangle())
    }

}

private struct InstantEditorView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var model: PanelModel
    private var text: Binding<String> {
        Binding(get: { model.draft?.body ?? "" }, set: { model.draft?.body = $0 })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "square.and.pencil").font(.system(size: 17)).foregroundStyle(store.accent.color)
                    .frame(width: 34, height: 34).background(store.accent.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 4) {
                    WarmHeading("即时编辑", size: 17)
                    Text(model.draft?.title ?? "").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { model.discardDraft() } label: { Image(systemName: "xmark").font(.system(size: 12)).frame(width: 24, height: 24) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("取消即时编辑")
            }.padding(.horizontal, 16).frame(height: 70)
            Divider().opacity(0.45)
            MarkdownTextEditor(text: text, focus: true, acceptsFiles: false, importFile: { _ in })
                .padding(10).background(Color(nsColor: .textBackgroundColor).opacity(0.65))
            HStack {
                Text("仅本次填入 · 不保存修改")
                Spacer()
                Text("\(model.draft?.body.count ?? 0) 字符")
            }.font(.system(size: 11)).foregroundStyle(.tertiary).padding(.horizontal, 16).padding(.vertical, 9)
            if let notice = model.notice {
                Text(notice).font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).frame(height: 64).background(store.accent.color.opacity(0.06))
            }
            Divider().opacity(0.45)
            HStack(spacing: 10) {
                Label(model.targetName.isEmpty ? "未选择输入框" : "填入 \(model.targetName)", systemImage: "text.cursor")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                if model.isInserting { ProgressView().controlSize(.small) }
                else {
                    Button("复制") {
                        guard let body = try? model.draft?.validatedBody() else { return }
                        _ = PromptPastePayload.text(body).write(to: .general)
                        model.notice = "已复制本次编辑内容。"
                    }.buttonStyle(.plain).foregroundStyle(store.accent.color)
                    Button("取消") { model.discardDraft() }
                    Button("完成") { model.completeDraft() }.buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command).disabled(model.draft?.canSubmit != true)
                }
            }.padding(.horizontal, 16).frame(height: 58)
        }
    }
}

private struct PanelSurface: ViewModifier {
    var theme: PanelTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.background(Color(nsColor: .windowBackgroundColor))
            } else if theme == .liquidGlass {
                if #available(macOS 26, *) {
                    content.glassEffect(.regular, in: .rect(cornerRadius: 16))
                } else { content.background(VisualEffect(material: .hudWindow)) }
            } else { content.background(Palette.background.opacity(0.82)).background(VisualEffect(material: .popover)) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.13), lineWidth: 0.75))
    }
}

struct PanelPreview: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                Text("搜索提示词").font(.system(size: 12)).foregroundStyle(.tertiary)
                Spacer()
                Keycap(text: "esc")
            }.padding(14)
            HStack(spacing: 17) {
                Text("全部").foregroundStyle(store.accent.color)
                Text("通用"); Text("AIGC"); Text("数据")
                Spacer()
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 15).padding(.bottom, 12)
            Divider().opacity(0.4)
            VStack(spacing: 3) {
                ForEach(Array(store.library.filtered(.all).prefix(3).enumerated()), id: \.element.id) { index, prompt in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(prompt.title).font(AppTypography.title(store.preferences.fontSize - 2)).lineLimit(1)
                            Text(prompt.excerpt).font(.system(size: store.preferences.fontSize - 3)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 12).padding(.vertical, 10)
                        .background(index == 0 ? store.accent.color.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .leading) { if index == 0 { RoundedRectangle(cornerRadius: 2).fill(store.accent.color).frame(width: 2.5).padding(.vertical, 10) } }
                }
            }.padding(6)
            Divider().opacity(0.4)
            HStack { Text("↑↓ 选择"); Spacer(); Text("↵ 填入") }.font(.system(size: 11)).foregroundStyle(.secondary).padding(13)
        }.modifier(PanelSurface(theme: store.preferences.theme))
            .shadow(color: .black.opacity(0.08), radius: 15, y: 6)
    }
}

private struct PromptPreviewCard: View {
    var prompt: Prompt
    var category: String
    var accent: Color
    var fontSize: Double
    var close: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "eye.fill").foregroundStyle(accent)
                WarmSectionLabel("内容预览")
                Text("只读").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(.primary.opacity(0.045), in: Capsule())
                Spacer()
                Text(category).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 22) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("关闭内容预览").accessibilityLabel("关闭内容预览")
            }.padding(.horizontal, 12).frame(height: 34)
                .background(accent.opacity(scheme == .dark ? 0.15 : 0.07))
            Divider().overlay(accent.opacity(0.16))
            VStack(alignment: .leading, spacing: 5) {
                Text(prompt.title).font(AppTypography.title(fontSize)).lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(prompt.body.count) 字符")
                    if !prompt.markdownDocuments.isEmpty { Label("\(prompt.markdownDocuments.count) 个 Markdown 附件", systemImage: "paperclip") }
                }.font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 8)
            PromptTextPreview(text: prompt.body, fontSize: fontSize - 1, contentID: prompt.id)
                .padding(.horizontal, 14).padding(.bottom, 10)

        }
        .background(scheme == .dark ? Color(hex: 0x20232A) : Color(hex: 0xF8FAFF))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.25), lineWidth: 1))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.65)).frame(width: 3).padding(.vertical, 12) }
        .shadow(color: .black.opacity(scheme == .dark ? 0.14 : 0.04), radius: 5, y: 2)
        .accessibilityElement(children: .contain).accessibilityLabel("提示词内容预览")
    }
}
