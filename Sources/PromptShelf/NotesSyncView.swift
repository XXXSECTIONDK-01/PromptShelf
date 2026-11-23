import SwiftUI
import PromptCore
import PromptUI

struct NotesSyncView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var model: NotesSyncModel
    @State private var direction = 0
    private var localPrompts: [Prompt] { store.library.filtered(.all, query: model.exportQuery) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SurfaceCard {
                    HStack(spacing: 14) {
                        CategoryIcon(symbol: "note.text", color: Color(hex: 0xD6A51D), size: 40)
                        VStack(alignment: .leading, spacing: 5) {
                            WarmHeading("Apple 备忘录", size: 18)
                            Text("按需同步所选笔记与 Markdown 附件。iCloud 跨设备同步由系统备忘录完成。")
                                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Button(model.accounts.isEmpty ? "连接备忘录" : "重新连接") { model.connect() }
                            .buttonStyle(.borderedProminent).disabled(model.busy)
                    }
                }
                if !model.accounts.isEmpty {
                    SurfaceCard {
                        HStack(spacing: 16) {
                            Text("备忘录账户").font(.system(size: 13, weight: .medium))
                            Picker("备忘录账户", selection: Binding(get: { model.accountID }, set: model.changeAccount)) {
                                ForEach(model.accounts) { Text($0.name).tag($0.id) }
                            }.labelsHidden().frame(maxWidth: 300)
                            Spacer()
                            Label(model.busy ? "同步中" : "手动同步", systemImage: model.busy ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }.disabled(model.busy)
                    }
                    Picker("同步方向", selection: $direction) {
                        Text("从备忘录导入").tag(0)
                        Text("导出到备忘录").tag(1)
                    }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: .infinity)
                    if direction == 0 { importSection } else { exportSection }
                } else {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("首次连接", systemImage: "lock.shield").font(.system(size: 14, weight: .medium))
                            Text("点击连接后，macOS 会请求自动化权限。允许词屿控制备忘录后，即可选择账户、文件夹与笔记。")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                            Text("仅在开始同步时读取或写入。不会上传到第三方服务，也不会在后台自动同步。")
                                .font(.system(size: 12)).foregroundStyle(.tertiary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if model.busy {
                    HStack(spacing: 10) { ProgressView().controlSize(.small); Text(model.status).font(.system(size: 12)) }
                }
                if let summary = model.summary {
                    Label(summary, systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(ColorToken.green.color)
                }
                if let error = model.error {
                    Label { Text(error).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.circle") }
                        .font(.system(size: 13)).foregroundStyle(.red).textSelection(.enabled)
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }.background(ThinScrollbars())
    }
    private var importSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Picker("文件夹", selection: Binding(get: { model.folderID }, set: model.changeFolder)) {
                        if model.folders.isEmpty { Text("无可用文件夹").tag("") }
                        ForEach(model.folders) { Text($0.path).tag($0.id) }
                    }.frame(maxWidth: .infinity)
                    Button { model.refresh() } label: { Label("刷新", systemImage: "arrow.clockwise") }.disabled(model.folderID.isEmpty)
                }
                NativeSearch(text: $model.query, placeholder: "搜索已加载的笔记标题").frame(height: 28)
                Divider().opacity(0.5)
                if model.filteredEntries.isEmpty {
                    Text(model.folderID.isEmpty ? "选择文件夹查看笔记" : "暂无匹配笔记").font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 24)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(model.filteredEntries) { entry in
                            Toggle(isOn: Binding(get: { model.selectedNotes.contains(entry.id) }, set: { selected in
                                if selected { model.selectedNotes.insert(entry.id) } else { model.selectedNotes.remove(entry.id) }
                            })) {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.name.isEmpty ? "未命名备忘录" : entry.name).font(AppTypography.title(15)).lineLimit(1)
                                        Text(entry.locked ? "已锁定 · 请先在备忘录中解锁" : entry.markdownCount > 0 ? "\(entry.markdownCount) 个 Markdown 附件" : "文本笔记")
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if entry.locked { Image(systemName: "lock").foregroundStyle(.tertiary) }
                                }.padding(.vertical, 9)
                            }.toggleStyle(.checkbox).disabled(entry.locked || (!model.selectedNotes.contains(entry.id) && model.selectedNotes.count >= 20))
                            Divider().opacity(0.3)
                        }
                    }
                }
                HStack {
                    Text("已加载 \(model.entries.count) / \(model.total) 条 · 已选 \(model.selectedNotes.count) 条")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if model.entries.count < model.total { Button("加载更多") { model.loadMore() } }
                }
                Divider().opacity(0.5)
                HStack(spacing: 16) {
                    Picker("导入分类", selection: $model.importCategory) {
                        ForEach(store.library.categories) { Text($0.name).tag($0.id) }
                    }.frame(maxWidth: 280)
                    Spacer()
                    Button("导入所选笔记") { model.pull(store: store) }.buttonStyle(.borderedProminent).disabled(model.selectedNotes.isEmpty)
                }
                Text("正文与 Markdown 附件一并导入。重复内容跳过；本地存在编辑时，先保留本地副本，再接收备忘录版本。")
                    .font(.system(size: 12)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }.disabled(model.busy)
        }
    }
    private var exportSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        WarmHeading("保存到「词屿」文件夹")
                        Text("首次导出时在所选账户中创建文件夹。Markdown 附件与正文保存在同一条笔记中。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(model.selectedPrompts.count) / 20").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                NativeSearch(text: $model.exportQuery, placeholder: "搜索待同步提示词").frame(height: 28)
                Divider().opacity(0.5)
                LazyVStack(spacing: 0) {
                    ForEach(localPrompts) { prompt in
                        Toggle(isOn: Binding(get: { model.selectedPrompts.contains(prompt.id) }, set: { selected in
                            if selected { model.selectedPrompts.insert(prompt.id) } else { model.selectedPrompts.remove(prompt.id) }
                        })) {
                            HStack {
                                Text(prompt.title).font(.system(size: 14)).lineLimit(1)
                                Spacer()
                                if !prompt.markdownDocuments.isEmpty { Label("\(prompt.markdownDocuments.count) MD", systemImage: "paperclip").font(.system(size: 11)).foregroundStyle(.secondary) }
                                if prompt.notesLink != nil { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11)).foregroundStyle(.tertiary) }
                            }.padding(.vertical, 10)
                        }.toggleStyle(.checkbox).disabled(!model.selectedPrompts.contains(prompt.id) && model.selectedPrompts.count >= 20)
                        Divider().opacity(0.3)
                    }
                }
                HStack {
                    Text("未改动的已同步内容自动跳过；更新以新笔记保存，保留已有历史。")
                        .font(.system(size: 12)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Button("同步所选提示词") { model.push(store: store) }.buttonStyle(.borderedProminent).disabled(model.selectedPrompts.isEmpty)
                }
            }.disabled(model.busy)
        }
    }
}
