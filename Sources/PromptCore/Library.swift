import Foundation

public struct PromptCategory: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var color: String
    public init(id: UUID = UUID(), name: String, symbol: String = "folder", color: String = "blue") {
        self.id = id; self.name = name; self.symbol = symbol; self.color = color
    }
    public static let generalID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

public struct Prompt: Identifiable, Codable, Hashable {
    public var id: UUID
    public var title: String
    public var body: String
    public var categoryID: UUID
    public var isFavorite: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var lastUsedAt: Date?
    public var useCount: Int
    public var markdown: MarkdownDocument?
    public var additionalMarkdown: [MarkdownDocument]?
    public var syncMarkdownBody: Bool?
    public var notesLink: NotesLink?
    public var markdownDocuments: [MarkdownDocument] { (markdown.map { [$0] } ?? []) + (additionalMarkdown ?? []) }
    public init(id: UUID = UUID(), title: String, body: String, categoryID: UUID = PromptCategory.generalID,
                isFavorite: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date(),
                lastUsedAt: Date? = nil, useCount: Int = 0, markdown: MarkdownDocument? = nil) {
        self.id = id; self.title = title; self.body = body; self.categoryID = categoryID
        self.isFavorite = isFavorite; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt; self.useCount = useCount
        self.markdown = markdown
    }
    public var excerpt: String {
        body.prefix(280).split(whereSeparator: { $0.isNewline }).joined(separator: " ")
    }
}

public enum PanelTheme: String, Codable, CaseIterable { case native, liquidGlass }
public enum AppearanceMode: String, Codable, CaseIterable { case system, light, dark }

public struct Hotkey: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public init(keyCode: UInt32 = 35, modifiers: UInt32 = 6144) {
        self.keyCode = keyCode; self.modifiers = modifiers
    }
    public var isReserved: Bool {
        // Preserve standard editing, window and application commands.
        modifiers == 256 && [0, 4, 6, 7, 8, 9, 12, 13, 46, 48, 49].contains(keyCode)
    }
    public var isValid: Bool {
        keyCode <= 127 && ![53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
            && modifiers & ~UInt32(256 | 512 | 2048 | 4096) == 0
            && modifiers & UInt32(256 | 2048 | 4096) != 0 && !isReserved
    }
}

public struct Preferences: Codable, Equatable {
    public var theme: PanelTheme = .native
    public var appearance: AppearanceMode = .system
    public var accent: String = "blue"
    public var fontSize: Double = 15
    public var panelWidth: Double = 500
    public var uiScale: Double = 1.2
    public var hotkey: Hotkey = Hotkey()
    public var styleRevision: Int = 2
    public init() {}
    private enum CodingKeys: String, CodingKey { case theme, appearance, accent, fontSize, panelWidth, uiScale, hotkey, styleRevision }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        theme = try values.decode(PanelTheme.self, forKey: .theme)
        appearance = try values.decode(AppearanceMode.self, forKey: .appearance)
        accent = try values.decode(String.self, forKey: .accent)
        fontSize = try values.decode(Double.self, forKey: .fontSize)
        panelWidth = try values.decode(Double.self, forKey: .panelWidth)
        uiScale = try values.decodeIfPresent(Double.self, forKey: .uiScale) ?? 1.2
        hotkey = try values.decode(Hotkey.self, forKey: .hotkey)
        let oldRevision = try values.decodeIfPresent(Int.self, forKey: .styleRevision) ?? 1
        if oldRevision < 2 {
            if fontSize == 13 { fontSize = 15 }
            if panelWidth == 540 { panelWidth = 500 }
        }
        styleRevision = 2
    }
}

public enum LibraryFilter: Hashable {
    case all, favorites, recent, category(UUID)
}

public struct PromptLibrary: Codable, Equatable {
    public var version: Int = 3
    public var categories: [PromptCategory]
    public var prompts: [Prompt]
    public var preferences: Preferences
    public init(categories: [PromptCategory], prompts: [Prompt], preferences: Preferences = Preferences()) {
        self.categories = categories; self.prompts = prompts; self.preferences = preferences
    }

    public func category(for prompt: Prompt) -> PromptCategory? {
        categories.first { $0.id == prompt.categoryID }
    }

    public func filtered(_ filter: LibraryFilter, query: String = "") -> [Prompt] {
        let terms = Self.normalized(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return prompts.filter { prompt in
            switch filter {
            case .all: break
            case .favorites: if !prompt.isFavorite { return false }
            case .recent: if prompt.lastUsedAt == nil { return false }
            case .category(let id): if prompt.categoryID != id { return false }
            }
            if terms.isEmpty { return true }
            let searchable = Self.normalized(prompt.title + " " + prompt.body + " " + (category(for: prompt)?.name ?? ""))
            return terms.allSatisfy { searchable.contains($0) }
        }.sorted { lhs, rhs in
            if filter == .recent, lhs.lastUsedAt != rhs.lastUsedAt {
                return (lhs.lastUsedAt ?? .distantPast) > (rhs.lastUsedAt ?? .distantPast)
            }
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public mutating func markUsed(_ id: UUID, at date: Date = Date()) {
        guard let i = prompts.firstIndex(where: { $0.id == id }) else { return }
        prompts[i].lastUsedAt = date; prompts[i].useCount += 1
    }

    public mutating func removeCategory(_ id: UUID) {
        guard id != PromptCategory.generalID else { return }
        for i in prompts.indices where prompts[i].categoryID == id { prompts[i].categoryID = PromptCategory.generalID }
        categories.removeAll { $0.id == id }
    }

    public static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    public func validate(checkContent: Bool = true) throws {
        guard (1...3).contains(version) else { throw LibraryError.invalid("当前应用不支持此资料库版本。请升级词屿后导入。") }
        guard !categories.isEmpty, categories.count <= 500, prompts.count <= 50_000 else {
            throw LibraryError.invalid("分类或提示词数量超出范围。")
        }
        let ids = Set(categories.map(\.id))
        guard ids.count == categories.count, Set(prompts.map(\.id)).count == prompts.count else {
            throw LibraryError.invalid("文件包含重复的条目编号。")
        }
        guard ids.contains(PromptCategory.generalID) else { throw LibraryError.invalid("文件缺少通用分类。") }
        var names = Set<String>()
        for category in categories {
            let name = Self.normalized(category.name)
            guard !name.isEmpty, category.name.count <= 40, names.insert(name).inserted else {
                throw LibraryError.invalid("分类名称不能为空、重复或超过 40 个字符。")
            }
        }
        for prompt in prompts {
            guard prompt.markdownDocuments.count <= 20, prompt.additionalMarkdown?.isEmpty != false || prompt.markdown != nil else {
                throw LibraryError.invalid("Markdown 附件数量或关联无效。")
            }
            if checkContent { for document in prompt.markdownDocuments { try document.validate() } }
            if let link = prompt.notesLink {
                guard !link.accountID.isEmpty, !link.noteID.isEmpty, link.remoteRevision.utf8.count <= 100_000,
                      link.localFingerprint.count == 64 else { throw LibraryError.invalid("备忘录同步记录无效。") }
            }
            guard ids.contains(prompt.categoryID) else { throw LibraryError.invalid("有提示词指向不存在的分类。") }
            guard !Self.normalized(prompt.title).isEmpty, prompt.title.count <= 120,
                  prompt.useCount >= 0 else { throw LibraryError.invalid("提示词标题或正文无效，或内容过长。") }
            if checkContent { try prompt.validateContent() }
        }
        guard (11...19).contains(preferences.fontSize), (440...680).contains(preferences.panelWidth),
              preferences.uiScale.isFinite, (0.8...1.5).contains(preferences.uiScale),
              ["blue", "violet", "green", "orange", "rose", "gray"].contains(preferences.accent),
              preferences.hotkey.isValid else {
            throw LibraryError.invalid("文件包含无效的外观设置或快捷键。")
        }
    }

    /// Merge without overwriting local edits or local preferences.
    public mutating func merge(_ incoming: PromptLibrary) throws -> Int {
        try incoming.validate()
        var merged = self
        var categoryMap: [UUID: UUID] = [:]
        for category in incoming.categories {
            if category.id == PromptCategory.generalID {
                categoryMap[category.id] = PromptCategory.generalID
            } else if let match = merged.categories.first(where: { Self.normalized($0.name) == Self.normalized(category.name) }) {
                categoryMap[category.id] = match.id
            } else {
                var copy = category
                if merged.categories.contains(where: { $0.id == copy.id }) { copy.id = UUID() }
                merged.categories.append(copy); categoryMap[category.id] = copy.id
            }
        }
        var added = 0
        for prompt in incoming.prompts {
            var copy = prompt
            copy.categoryID = categoryMap[prompt.categoryID]!
            if merged.prompts.contains(where: { $0.title == copy.title && $0.body == copy.body && $0.categoryID == copy.categoryID && $0.markdownDocuments == copy.markdownDocuments }) { continue }
            if merged.prompts.contains(where: { $0.id == copy.id }) { copy.id = UUID() }
            merged.prompts.append(copy); added += 1
        }
        try merged.validate()
        self = merged
        return added
    }
}

public enum LibraryError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

public extension Prompt {
    func validateContent() throws {
        guard body.utf8.count <= 20_000_000,
              body.unicodeScalars.contains(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }) else {
            throw LibraryError.invalid("提示词正文为空或超过 20 MB。")
        }
    }
}
