import Foundation

public extension PromptLibrary {
    static var seed: PromptLibrary {
        let general = PromptCategory(id: PromptCategory.generalID, name: "通用", symbol: "square.grid.2x2", color: "blue")
        let creative = PromptCategory(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "AIGC", symbol: "sparkles", color: "violet")
        let data = PromptCategory(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "数据生成", symbol: "chart.bar.xaxis", color: "green")
        let writing = PromptCategory(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "写作与表达", symbol: "pencil.line", color: "orange")
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let examples: [(String, String, UUID, Bool)] = [
            ("把想法变成行动计划", "请帮我把下面的想法整理成可以执行的行动计划。\n\n请先明确目标与交付物，再拆解具体步骤、优先级、依赖条件和验收标准。对于信息不足的地方，请标明假设，只询问真正会影响执行的关键问题。\n\n请用简洁、具体的语言输出，让我能直接开始第一步。\n\n我的想法：\n", general.id, true),
            ("让表达更清楚", "请润色下面这段文字，在保留原意和语气的前提下，让表达更清楚、自然、简洁。\n\n要求：\n1. 使用具体、直接的语言，删除重复和空泛措辞。\n2. 保留必要的信息和细节，不擅自添加事实。\n3. 先给出修改后的文本，再简要说明关键调整。\n\n原文：\n", writing.id, true),
            ("深入理解一个概念", "请帮我理解下面的概念。先用日常语言解释，再给出一个具体例子，最后说明它的适用范围、常见误解以及与相近概念的区别。\n\n请循序渐进；涉及专业术语时先解释术语，不要假设我已经了解背景。\n\n概念：\n", general.id, false),
            ("高质量图像提示词", "请把我的画面想法转化为可直接用于图像生成的提示词。\n\n请明确主体、场景、构图、光线、色彩、材质与情绪，保持视觉元素一致。避免互相冲突的描述，优先使用具体可见的细节。\n\n输出一版中文和一版英文提示词，并提供三个风格方向供我选择。\n\n画面想法：\n", creative.id, true),
            ("分镜与镜头设计", "请根据以下故事设计一组连续分镜。逐个镜头说明景别、主体动作、场景、光线、运镜和建议时长。确保角色特征、服装与空间关系在镜头之间保持连续。\n\n先给出整体视觉方向，再以表格呈现分镜。\n\n故事：\n", creative.id, false),
            ("生成结构化测试数据", "请根据下面的数据结构与约束，生成一组虚构的测试数据。\n\n要求：\n1. 字段类型正确，关联关系一致。\n2. 覆盖正常值、边界值和可允许的空值。\n3. 不包含真实个人信息。\n4. 输出可解析的 JSON，不要在 JSON 中加入注释。\n5. 如果约束互相冲突，请先指出。\n\n字段、数量与约束：\n", data.id, true),
            ("为数据建立验收规则", "请根据以下数据需求，整理字段级与记录级的数据验收规则。\n\n请覆盖类型、取值范围、唯一性、缺失值、跨字段逻辑和关联完整性。以表格列出规则、失败示例、严重程度与修复建议。\n\n数据需求：\n", data.id, false),
            ("总结长文与会议记录", "请整理以下内容，输出：\n\n一、核心结论：用三到五条表达最重要的信息。\n二、关键依据：保留支撑结论的事实与数字。\n三、行动项：列出具体任务、负责人和时间；未说明的内容标注待确认。\n四、未解决的问题。\n\n不要补充原文中不存在的信息。\n\n内容：\n", general.id, false),
            ("写一封得体的邮件", "请根据以下背景起草一封邮件。\n\n语气专业、自然、得体；开头明确来意，中间给出必要背景，结尾说明希望对方采取的行动。避免冗长客套。请提供邮件主题与正文。\n\n收件人、背景、目的与语气要求：\n", writing.id, false)
        ]
        let prompts = examples.enumerated().map { index, item in
            Prompt(id: UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", index + 1))!, title: item.0, body: item.1,
                   categoryID: item.2, isFavorite: item.3, createdAt: date, updatedAt: date.addingTimeInterval(Double(-index)))
        }
        return PromptLibrary(categories: [general, creative, data, writing], prompts: prompts)
    }
}
