import SwiftUI
import PromptCore
import PromptUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var categoryDraft: CategoryDraft?
    @State private var deletingCategory: PromptCategory?
    @State private var droppingMarkdown = false
    @State private var selectedRowBounds: CGRect?

    var body: some View {
        GeometryReader { windowGeometry in
          HStack(spacing: 0) {
            sidebar
                .background {
                    FloatingSidebarSurface(selectionY: sidebarReflectionY(height: windowGeometry.size.height))
                        .padding(.top, -28)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: sidebarReflectionY(height: windowGeometry.size.height))
                }
                .padding(.horizontal, 8).padding(.vertical, 8)
                .frame(width: 202)
            VStack(spacing: 0) {
                if store.page == .library {
                    GeometryReader { geometry in
                      HStack(spacing: 0) {
                        promptList.frame(width: min(340, max(290, geometry.size.width * 0.34)))
                        Divider().opacity(0.55)
                        if let prompt = store.selectedPrompt {
                            PromptDetail(store: store, prompt: prompt)
                        } else {
                            EmptyState(title: "未选择提示词", detail: "选择提示词查看正文，或新建、导入 Markdown 文件。")
                        }
                      }
                      .onDrop(of: [UTType.fileURL], isTargeted: $droppingMarkdown) { store.acceptMarkdownDrop($0) }
                      .overlay {
                          if droppingMarkdown {
                              RoundedRectangle(cornerRadius: 12).fill(store.accent.color.opacity(0.08))
                                  .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(store.accent.color, lineWidth: 2))
                                  .overlay {
                                      Label("导入 Markdown", systemImage: "doc.badge.plus").font(.system(size: 18, weight: .semibold))
                                          .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                  }.padding(8).allowsHitTesting(false)
                          }
                      }
                    }
                } else { header; Divider().opacity(0.5); if store.page == .notes { NotesSyncView(store: store, model: store.notesSync) } else { SettingsView(store: store) } }
            }
            .background(Palette.background)
        }
          .coordinateSpace(name: "libraryColumns")
          .onPreferenceChange(SelectedPromptRowBounds.self) { selectedRowBounds = $0 }
        }
        .padding(.top, 28)
        .background(Palette.sidebar)
        .ignoresSafeArea(.container, edges: .top)
        .tint(store.accent.color)
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(store.accent.color)
                    Text(toast).font(.system(size: 12)).lineLimit(2)
                    if store.canUndo { Button("撤销") { store.undo() }.buttonStyle(.plain).foregroundStyle(store.accent.color) }
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.09), radius: 10, y: 3)
                .padding(.bottom, 22)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: store.toast)
        .sheet(item: $store.editor) { draft in
            ScaledPromptSheet(scale: store.preferences.uiScale) { height in PromptEditor(store: store, initial: draft, height: height) }
        }
        .sheet(item: $categoryDraft) { draft in
            CategoryEditor(store: store, draft: draft).modifier(InterfaceScale(scale: store.preferences.uiScale))
        }
        .alert("操作未完成", isPresented: Binding(get: { store.errorMessage != nil && store.editor == nil && categoryDraft == nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("确定", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .confirmationDialog("删除「\(deletingCategory?.name ?? "")」？", isPresented: Binding(get: { deletingCategory != nil }, set: { if !$0 { deletingCategory = nil } }), titleVisibility: .visible) {
            Button("删除分类并将提示词移至通用", role: .destructive) {
                if let category = deletingCategory { store.deleteCategory(category) }; deletingCategory = nil
            }
        } message: { Text("该分类中的提示词会保留。") }
        .alert("合并导入提示词库", isPresented: Binding(get: { store.pendingImport != nil }, set: { if !$0 { store.pendingImport = nil } })) {
            Button("取消", role: .cancel) { store.pendingImport = nil }
            Button("合并导入") { store.confirmImport() }
        } message: {
            Text("文件包含 \(store.pendingImport?.prompts.count ?? 0) 条提示词。相同内容会跳过，现有提示词和外观设置会保留。")
        }
        .onChange(of: store.resultsRevision) { _, _ in reconcileSelection() }
        .modifier(InterfaceScale(scale: store.preferences.uiScale))
    }

    private func sidebarReflectionY(height: CGFloat) -> CGFloat? {
        guard store.page == .library, let rect = selectedRowBounds, height > 0,
              rect.maxY > 75, rect.minY < height - 32 else { return nil }
        return min(1, max(0, (rect.midY + 20) / height))
    }

    private func reconcileSelection() {
        if !store.visiblePrompts.contains(where: { $0.id == store.selectedID }) { store.selectedID = store.visiblePrompts.first?.id }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandWordmark().zIndex(2)
                .padding(.horizontal, 19).padding(.top, 11).padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    sectionLabel("内容库")
                    navigationRow("全部提示词", symbol: "square.stack.3d.up", color: ColorToken.blue.color, count: store.library.prompts.count, selected: store.page == .library && store.filter == .all) { store.selectFilter(.all) }
                    navigationRow("收藏", symbol: "star", color: Palette.gold, count: store.library.prompts.filter(\.isFavorite).count, selected: store.page == .library && store.filter == .favorites) { store.selectFilter(.favorites) }
                    navigationRow("最近使用", symbol: "clock", color: ColorToken.green.color, selected: store.page == .library && store.filter == .recent) { store.selectFilter(.recent) }

                    HStack {
                        sectionLabel("分类")
                        Spacer()
                        IconButton(symbol: "plus", help: "新建分类") { categoryDraft = .new }
                    }.padding(.top, 12)
                    ForEach(store.library.categories) { category in
                        navigationRow(category.name, symbol: category.symbol, color: ColorToken.color(category.color),
                                      count: store.library.prompts.filter { $0.categoryID == category.id }.count,
                                      selected: store.page == .library && store.filter == .category(category.id)) { store.selectFilter(.category(category.id)) }
                            .contextMenu {
                                Button("编辑分类") { categoryDraft = CategoryDraft(category: category) }
                                if category.id != PromptCategory.generalID {
                                    Button("删除分类…", role: .destructive) { deletingCategory = category }
                                }
                            }
                    }

                    sectionLabel("应用").padding(.top, 18)
                    navigationRow("外观", symbol: "paintpalette", color: ColorToken.violet.color, selected: store.page == .appearance) { store.page = .appearance }
                    navigationRow("快捷键与填入", symbol: "keyboard", color: ColorToken.blue.color, selected: store.page == .behavior) { store.page = .behavior }
                    navigationRow("数据与备份", symbol: "externaldrive", color: ColorToken.green.color, selected: store.page == .data) { store.page = .data }
                    navigationRow("备忘录同步", symbol: "note.text", color: Palette.gold, selected: store.page == .notes) { store.page = .notes }
                    navigationRow("关于词屿", symbol: "info.circle", color: ColorToken.rose.color, selected: store.page == .about) { store.page = .about }
                }.padding(.horizontal, 9)
            }.scrollIndicators(.hidden).background(ThinScrollbars())
            HStack(spacing: 7) {
                Button { store.openPanel?() } label: { Image(systemName: "keyboard"); Text(store.preferences.hotkey.display).font(.system(size: 11, weight: .medium)) }.buttonStyle(.plain)
                Spacer(minLength: 0)
                if store.isSaving { ProgressView().controlSize(.mini) }
                Text(store.isSaving ? "正在保存" : "本地资料库").font(.system(size: 9)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 18).padding(.vertical, 13)
                .overlay(alignment: .top) { Divider().padding(.horizontal, 15) }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        WarmSectionLabel(title).padding(.leading, 10).padding(.bottom, 6)
    }
    private func navigationRow(_ title: String, symbol: String, color: Color, count: Int? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(color).frame(width: 15)
                Text(title).font(.system(size: 13, weight: .regular)).lineLimit(1)
                Spacer(minLength: 3)
                if let count { Text("\(count)").font(.system(size: 11, design: .rounded)).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 9).frame(height: 30)
            .background(selected ? Color.primary.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(AppTypography.title(27))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            if store.page == .library {
                IconButton(symbol: "rectangle.on.rectangle", help: "打开快捷面板") { store.openPanel?() }
                Button { store.newPrompt() } label: { Label("新建提示词", systemImage: "plus").font(.system(size: 12, weight: .medium)).padding(.horizontal, 5).padding(.vertical, 3) }
                    .buttonStyle(.borderedProminent).controlSize(.regular).keyboardShortcut("n", modifiers: .command)
            }
        }.padding(.horizontal, 27).frame(height: 76)
    }
    private var title: String {
        switch store.page { case .library: return store.pageTitle; case .appearance: return "外观"; case .behavior: return "快捷键与填入"; case .data: return "数据与备份"; case .notes: return "备忘录同步"; case .about: return "关于词屿" }
    }
    private var subtitle: String {
        switch store.page {
        case .library: return "\(store.visiblePrompts.count) 条提示词"
        case .appearance: return "设置主题、显示模式、强调色与面板尺寸。"
        case .behavior: return "设置全局快捷键、输入权限与附件操作。"
        case .data: return "管理本地内容、文件导入与资料库备份。"
        case .notes: return "在词屿与 Apple 备忘录之间同步正文和 Markdown 附件。"
        case .about: return "应用版本与产品信息。"
        }
    }
    private var promptList: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(store.pageTitle).font(AppTypography.title(19))
                    Text("\(store.visiblePrompts.count)").font(.system(size: 12)).foregroundStyle(.tertiary)
                    Spacer()
                    IconButton(symbol: "square.and.arrow.down", help: "导入 Markdown") { store.chooseMarkdownFiles() }
                    IconButton(symbol: "plus", help: "新建提示词") { store.newPrompt() }
                }
                NativeSearch(text: $store.query, placeholder: "搜索标题与内容", fontSize: 12).frame(height: 28)
            }.padding(.horizontal, 14).padding(.vertical, 14)
            Divider().opacity(0.4)
            if store.isLoading {
                ProgressView("正在载入资料库").font(.system(size: 12)).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.visiblePrompts.isEmpty {
                EmptyState(symbol: store.query.isEmpty ? "tray" : "magnifyingglass", title: store.query.isEmpty ? "暂无提示词" : "没有找到提示词", detail: store.query.isEmpty ? "新建提示词或拖入 Markdown 文件。" : "调整关键词或切换分类。")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.visiblePrompts) { prompt in
                            PromptListRow(store: store, prompt: prompt, selected: store.selectedID == prompt.id)
                        }
                    }.padding(.bottom, 12)
                }.scrollIndicators(.hidden).background(ThinScrollbars())
            }
            HStack { Text("\(store.visiblePrompts.count) 条提示词"); Spacer(); Text(store.isImporting ? "正在导入…" : "可拖入 Markdown") }
                .font(.system(size: 11)).foregroundStyle(.tertiary).padding(.horizontal, 14).frame(height: 32)
        }.background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }
}

struct PromptListRow: View {
    @ObservedObject var store: AppStore
    var prompt: Prompt
    var selected: Bool
    @State private var hovering = false
    var body: some View {
        let category = store.library.category(for: prompt)
        Button { store.selectedID = prompt.id } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(prompt.title).font(AppTypography.title(15)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if prompt.markdown != nil { Text("MD").font(.system(size: 9, weight: .semibold)).foregroundStyle(selected ? Color.white : store.accent.color).padding(.horizontal, 4).padding(.vertical, 2).background(selected ? Color.white.opacity(0.16) : store.accent.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 3)) }
                    if prompt.isFavorite { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Palette.gold) }
                }
                Text(prompt.excerpt).font(.system(size: 12)).foregroundStyle(selected ? Color.white.opacity(0.86) : Color.secondary).lineLimit(2).lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Label(category?.name ?? "通用", systemImage: category?.symbol ?? "folder").labelStyle(.titleAndIcon)
                        .foregroundStyle(ColorToken.categoryLabel(category?.color ?? "blue", selected: selected))
                    Spacer()
                    if prompt.useCount > 0 { Text("已使用 \(prompt.useCount) 次") }
                }.font(.system(size: 10)).foregroundStyle(selected ? Color.white.opacity(0.72) : Color.secondary.opacity(0.65))
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 10).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? ColorToken.blue.color : (hovering ? Color.primary.opacity(0.025) : .clear), in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 15) }
            .contentShape(Rectangle())
            .background {
                if selected {
                    GeometryReader { geometry in
                        Color.clear.preference(key: SelectedPromptRowBounds.self, value: geometry.frame(in: .named("libraryColumns")))
                    }
                }
            }
        }.buttonStyle(.plain).padding(.horizontal, 8).onHover { hovering = $0 }
            .modifier(MarkdownFileDrag(store: store, prompt: prompt))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .contextMenu {
                Button("编辑") { store.edit(prompt) }
                Button(prompt.isFavorite ? "取消收藏" : "收藏") { store.toggleFavorite(prompt) }
                Button("复制正文") { store.copy(prompt) }
                if prompt.markdown != nil { Button("显示 Markdown 文件") { store.revealMarkdown(prompt) } }
                Button("创建副本") { store.duplicate(prompt) }
                Divider()
                Button("删除", role: .destructive) { store.delete(prompt) }
            }
    }
}

struct PromptDetail: View {
    @ObservedObject var store: AppStore
    var prompt: Prompt
    var body: some View {
        let category = store.library.category(for: prompt)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Text(prompt.title).font(AppTypography.title(27)).tracking(-0.5).lineSpacing(4).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    IconButton(symbol: "rectangle.on.rectangle", help: "打开快捷面板") { store.openPanel?() }
                }
                HStack(spacing: 9) {
                    Label(category?.name ?? "通用", systemImage: category?.symbol ?? "folder")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(store.accent.color)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(store.accent.color.opacity(0.10), in: Capsule())
                    if prompt.isFavorite {
                        Label("已收藏", systemImage: "star.fill").font(.system(size: 12)).foregroundStyle(Palette.gold)
                    }
                    Spacer(minLength: 0)
                    Text(prompt.updatedAt, style: .date).font(.system(size: 12)).foregroundStyle(.tertiary)
                }
            }.padding(.horizontal, 28).padding(.top, 36).padding(.bottom, 20)
            Divider().opacity(0.5)
            if !prompt.markdownDocuments.isEmpty {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(prompt.markdownDocuments.enumerated()), id: \.offset) { _, document in
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text").font(.system(size: 19)).foregroundStyle(store.accent.color)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(document.fileName).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                    Text("Markdown · 拖动添加文件附件").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Button("显示文件") { store.revealMarkdown(prompt, document: document) }.font(.system(size: 12))
                            }.padding(12).background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 8))
                                .onDrag { store.fileProvider(for: prompt, document: document) }
                                .help("拖动文件至支持附件的聊天框")
                        }
                    }
                }.background(ThinScrollbars()).frame(height: min(138, CGFloat(prompt.markdownDocuments.count) * 62))
                    .padding(.horizontal, 24).padding(.top, 16)
            }
            PromptTextPreview(text: prompt.body, fontSize: 15, contentID: prompt.id)
                .padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 8)
            HStack(spacing: 5) {
                Image(systemName: "keyboard")
                Text("\(store.preferences.hotkey.display) 唤起 · 选择后填入")
                Spacer()
                if prompt.useCount > 0 { Text("已使用 \(prompt.useCount) 次") }
            }.font(.system(size: 11)).foregroundStyle(.tertiary).padding(.horizontal, 24).padding(.bottom, 12)
            Divider().opacity(0.5)
            HStack(spacing: 10) {
                Button { store.edit(prompt) } label: { Label("编辑", systemImage: "square.and.pencil") }.buttonStyle(.bordered).foregroundStyle(store.accent.color)
                Button { store.copy(prompt) } label: { Label("复制", systemImage: "doc.on.doc") }.buttonStyle(.bordered).foregroundStyle(store.accent.color)
                Divider().frame(height: 18).padding(.horizontal, 2)
                IconButton(symbol: "plus.square.on.square", help: "创建副本") { store.duplicate(prompt) }
                IconButton(symbol: prompt.isFavorite ? "star.fill" : "star", help: prompt.isFavorite ? "取消收藏" : "收藏提示词") { store.toggleFavorite(prompt) }
                Spacer(minLength: 0)
                IconButton(symbol: "trash", help: "删除提示词") { store.delete(prompt) }
            }.font(.system(size: 13)).controlSize(.regular).padding(.horizontal, 24).padding(.vertical, 13)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct CategoryDraft: Identifiable {
    var id = UUID()
    var category: PromptCategory?
    static var new: CategoryDraft { CategoryDraft(category: nil) }
}

struct MarkdownFileDrag: ViewModifier {
    @ObservedObject var store: AppStore
    var prompt: Prompt
    func body(content: Content) -> some View {
        if prompt.markdown != nil { content.onDrag { store.fileProvider(for: prompt) } }
        else { content }
    }
}
