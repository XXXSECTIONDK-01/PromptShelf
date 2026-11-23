import SwiftUI
import PromptCore
import PromptUI
import UniformTypeIdentifiers

struct PromptEditor: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PromptDraft
    @State private var confirmDiscard = false
    @State private var pendingMarkdown: MarkdownDocument?
    private let original: PromptDraft
    private let editorHeight: CGFloat
    init(store: AppStore, initial: PromptDraft, height: CGFloat = 720) { self.store = store; original = initial; editorHeight = height; _draft = State(initialValue: initial) }
    private var changed: Bool { draft.prompt != original.prompt }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                CategoryIcon(symbol: "square.and.pencil", color: store.accent.color, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.isNew ? "新建提示词" : "编辑提示词").font(AppTypography.title(23))
                    Text("编辑正文、分类与关联文件").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                WarmSectionLabel("标题")
                TextField("提示词标题", text: $draft.prompt.title).font(AppTypography.title(16)).textFieldStyle(.roundedBorder).controlSize(.large)
            }
            HStack {
                Picker("分类", selection: $draft.prompt.categoryID) { ForEach(store.library.categories) { Text($0.name).tag($0.id) } }.frame(maxWidth: 280)
                Spacer()
                Toggle("收藏", isOn: $draft.prompt.isFavorite).toggleStyle(.checkbox)
            }.font(.system(size: 14))
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    WarmSectionLabel("提示词正文")
                    Spacer()
                    Text("\(draft.prompt.body.count) 字符").font(.system(size: 12)).foregroundStyle(.tertiary)
                }
                MarkdownTextEditor(text: $draft.prompt.body, importFile: receiveMarkdown)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.10), lineWidth: 1))
                    .overlay(alignment: .topLeading) {
                        if draft.prompt.body.isEmpty {
                            Text("输入正文，或拖入 Markdown 文件").font(.system(size: 15)).foregroundStyle(.tertiary)
                                .padding(.horizontal, 15).padding(.top, 13).allowsHitTesting(false)
                        }
                    }
                HStack(spacing: 8) {
                    Image(systemName: draft.prompt.markdown == nil ? "doc.badge.plus" : "doc.text")
                    if let document = draft.prompt.markdown {
                        Text(document.fileName).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button("更换文件…", action: chooseMarkdown)
                        Button("解除关联") { draft.prompt.markdown = nil; draft.prompt.additionalMarkdown = nil; draft.prompt.syncMarkdownBody = nil }
                    } else {
                        Text("支持 .md、.markdown，单个文件最大 20 MB").foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button("导入文件…", action: chooseMarkdown)
                    }
                }.font(.system(size: 12)).foregroundStyle(.secondary)
                if let additional = draft.prompt.additionalMarkdown, !additional.isEmpty {
                    Text("另有关联 Markdown 附件 \(additional.count) 个，可在详情页查看。").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if draft.prompt.markdown != nil {
                    Text(draft.prompt.syncMarkdownBody == false ? "关联文件独立保存，正文编辑不修改附件。" : "保存正文时同步更新关联的 Markdown 副本。").font(.system(size: 12)).foregroundStyle(.tertiary)
                }
            }
            if let error = store.errorMessage { Text(error).font(.system(size: 13)).foregroundStyle(.red).lineLimit(3) }
            HStack {
                Text("内容保存在本机").font(.system(size: 12)).foregroundStyle(.tertiary)
                Spacer()
                Button("取消") { if changed { confirmDiscard = true } else { dismiss() } }.keyboardShortcut(.cancelAction)
                Button("保存提示词") { _ = store.save(draft) }.buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command)
                    .disabled(draft.prompt.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.prompt.body.unicodeScalars.contains(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }))
            }
        }.padding(24).frame(width: 640, height: editorHeight).tint(store.accent.color)
            .interactiveDismissDisabled(changed)
            .confirmationDialog("放弃尚未保存的修改？", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { store.errorMessage = nil; dismiss() }
                Button("继续编辑", role: .cancel) {}
            }
            .confirmationDialog("替换当前正文？", isPresented: Binding(get: { pendingMarkdown != nil }, set: { if !$0 { pendingMarkdown = nil } }), titleVisibility: .visible) {
                Button("替换并关联文件") { if let document = pendingMarkdown { applyMarkdown(document) }; pendingMarkdown = nil }
                Button("取消", role: .cancel) { pendingMarkdown = nil }
            } message: { Text("当前正文将替换为文件内容。保存后生效，原始文件不受影响。") }
            .onAppear { store.errorMessage = nil }
    }
    private func chooseMarkdown() {
        let panel = NSOpenPanel(); panel.title = "导入 Markdown"; panel.prompt = "导入"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { receiveMarkdown(url) }
    }
    private func receiveMarkdown(_ url: URL) {
        Task {
            do {
                let document = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try MarkdownDocument.read(url)
                }.value
                if draft.prompt.body.isEmpty { applyMarkdown(document) }
                else { pendingMarkdown = document }
            } catch { store.errorMessage = error.localizedDescription }
        }
    }

    private func applyMarkdown(_ document: MarkdownDocument) {
        do {
            draft.prompt.body = try document.text; draft.prompt.markdown = document; draft.prompt.syncMarkdownBody = true
            if draft.prompt.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft.prompt.title = document.title }
            store.errorMessage = nil
        } catch { store.errorMessage = error.localizedDescription }
    }

}

struct CategoryEditor: View {
    @ObservedObject var store: AppStore
    var draft: CategoryDraft
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = "folder"
    @State private var color = "blue"
    private let symbols = ["folder", "square.grid.2x2", "sparkles", "chart.bar.xaxis", "pencil.line", "terminal", "briefcase", "book", "camera", "lightbulb"]
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(draft.category == nil ? "新建分类" : "编辑分类").font(AppTypography.title(23))
            HStack(spacing: 14) {
                CategoryIcon(symbol: symbol, color: ColorToken.color(color), size: 42)
                TextField("分类名称", text: $name).textFieldStyle(.roundedBorder).controlSize(.large)
            }
            VStack(alignment: .leading, spacing: 11) {
                Text("图标").font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(symbols, id: \.self) { item in
                        Button { symbol = item } label: {
                            Image(systemName: item).frame(width: 30, height: 30)
                                .background(symbol == item ? store.accent.color.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).accessibilityLabel(item)
                    }
                }
            }
            HStack(spacing: 12) {
                Text("颜色").font(.system(size: 13)).foregroundStyle(.secondary)
                ForEach(ColorToken.allCases, id: \.rawValue) { item in
                    Button { color = item.rawValue } label: {
                        Circle().fill(item.color).frame(width: 21, height: 21)
                            .overlay { if color == item.rawValue { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) } }
                    }.buttonStyle(.plain).accessibilityLabel(item.title)
                }
            }
            if let error = store.errorMessage { Text(error).font(.system(size: 13)).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { store.errorMessage = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存分类") {
                    if store.saveCategory(id: draft.category?.id, name: name, symbol: symbol, color: color) { dismiss() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 410).tint(store.accent.color)
            .onAppear {
                if let category = draft.category { name = category.name; symbol = category.symbol; color = category.color }
                store.errorMessage = nil
            }
    }
}
