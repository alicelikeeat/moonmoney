import Foundation
import FoundationModels
import SwiftData
import Vision

/// One record parsed from natural language or a screenshot, before saving.
struct RecordDraft: Identifiable, Hashable {
    let id = UUID()
    var kind: RecordKind = .expense
    var cents: Int = 0
    var categoryID: UUID?
    var accountID: UUID?
    var note: String = ""
    var date: Date = .now
    var include = true
}

enum ParserEngine: String {
    case appleIntelligence = "Apple 智能"
    case rules = "本地规则"
}

@MainActor
enum SmartParser {
    // MARK: Availability

    static var isAIAvailable: Bool {
        guard AppSettings.shared.aiEnabled else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var aiStatusText: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "可用"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "此设备不支持"
            case .appleIntelligenceNotEnabled: return "请在设置中开启 Apple 智能"
            case .modelNotReady: return "模型下载中"
            @unknown default: return "暂不可用"
            }
        }
    }

    // MARK: Entry point

    /// Parses free text into drafts, using Apple Intelligence when possible.
    static func parse(_ text: String, context: ModelContext) async -> (drafts: [RecordDraft], engine: ParserEngine) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ([], .rules) }
        let catalog = Catalog(context: context)

        if isAIAvailable, let drafts = try? await parseWithAI(trimmed, catalog: catalog), !drafts.isEmpty {
            return (drafts, .appleIntelligence)
        }
        return (RuleParser.parse(trimmed, catalog: catalog), .rules)
    }

    /// Saves drafts as records.
    @discardableResult
    static func save(_ drafts: [RecordDraft], context: ModelContext) -> [Record] {
        let catalog = Catalog(context: context)
        var saved: [Record] = []
        for draft in drafts where draft.include && draft.cents > 0 {
            let category = catalog.categories.first { $0.uuid == draft.categoryID }
                ?? catalog.categories.first { $0.kind == draft.kind }
            let account = catalog.accounts.first { $0.uuid == draft.accountID } ?? DataStore.defaultAccount(in: context)
            let record = Record(kind: draft.kind, amountCents: draft.cents, date: draft.date, note: draft.note,
                                category: category, account: account, ledgerID: AppSettings.shared.currentLedgerID)
            context.insert(record)
            saved.append(record)
        }
        try? context.save()
        AppServices.recordsChanged(saved, context: context)
        return saved
    }

    // MARK: Apple Intelligence

    private static func parseWithAI(_ text: String, catalog: Catalog) async throws -> [RecordDraft] {
        let expenseNames = catalog.categories.filter { $0.kind == .expense }.map(\.name).joined(separator: "、")
        let incomeNames = catalog.categories.filter { $0.kind == .income }.map(\.name).joined(separator: "、")
        let accountNames = catalog.accounts.map(\.name).joined(separator: "、")
        let instructions = """
        你是记账助手，把用户的一句话拆成若干笔账。
        支出分类：\(expenseNames)
        收入分类：\(incomeNames)
        账户：\(accountNames)
        今天是 \(Date.now.zh("yMMMdEEEE"))。只输出文本里真实出现的金额，不要编造。
        """
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: text, generating: AIResult.self)
        let cal = Calendar.current
        return response.content.items.compactMap { item -> RecordDraft? in
            guard item.amount > 0 else { return nil }
            var draft = RecordDraft()
            draft.kind = item.kind.lowercased().contains("income") ? .income : .expense
            draft.cents = Money.cents(item.amount)
            draft.note = item.note.trimmingCharacters(in: .whitespaces)
            draft.categoryID = catalog.category(named: item.category, kind: draft.kind)?.uuid
                ?? catalog.guessCategory(for: draft.note + item.category, kind: draft.kind)?.uuid
            draft.accountID = catalog.account(mentionedIn: item.account)?.uuid
                ?? catalog.account(mentionedIn: text)?.uuid
            let offset = max(-60, min(0, item.dayOffset))
            draft.date = cal.date(byAdding: .day, value: offset, to: .now) ?? .now
            return draft
        }
    }

    /// One-paragraph AI commentary for a report. Returns nil when AI is unavailable.
    static func commentary(for facts: String) async -> String? {
        guard isAIAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
        你是一位温和、务实的理财教练。根据用户的消费数据写一段 80~140 字的中文点评：
        先肯定做得好的地方，再指出 1~2 个最值得注意的问题，最后给一条具体可执行的建议。不要使用 Markdown。
        """)
        return try? await session.respond(to: facts).content
    }

    // MARK: Screenshot OCR

    /// Recognizes text in a payment screenshot and turns it into drafts.
    static func parseScreenshot(_ data: Data, context: ModelContext) async -> (drafts: [RecordDraft], text: String) {
        let lines = (try? await recognizeText(data)) ?? []
        let text = lines.joined(separator: "\n")
        let catalog = Catalog(context: context)
        if let draft = ScreenshotParser.parse(lines: lines, catalog: catalog) {
            return ([draft], text)
        }
        // Fall back to the general parser over the recognized text.
        let result = await parse(text, context: context)
        return (Array(result.drafts.prefix(1)), text)
    }

    static func recognizeText(_ data: Data) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [Locale.Language(identifier: "zh-Hans"), Locale.Language(identifier: "en-US")]
        let observations = try await request.perform(on: data)
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }
}

// MARK: - Apple Intelligence schema

@Generable
struct AIItem {
    @Guide(description: "收支类型：支出填 expense，收入填 income")
    var kind: String
    @Guide(description: "金额，单位是元，正数")
    var amount: Double
    @Guide(description: "从给定分类列表中选出最匹配的一个分类名称，必须与列表完全一致")
    var category: String
    @Guide(description: "用户提到的付款账户名称（例如 微信、支付宝、现金、信用卡），没提到就填空字符串")
    var account: String
    @Guide(description: "简短备注，例如商户名或买了什么，不超过 12 个字")
    var note: String
    @Guide(description: "相对今天的天数：今天 0，昨天 -1，前天 -2")
    var dayOffset: Int
}

@Generable
struct AIResult {
    @Guide(description: "文本中提到的每一笔收支")
    var items: [AIItem]
}

// MARK: - Catalog

/// Snapshot of categories and accounts for matching names.
@MainActor
struct Catalog {
    let categories: [BillCategory]
    let accounts: [Account]

    init(context: ModelContext) {
        categories = (try? context.fetch(FetchDescriptor<BillCategory>(
            predicate: #Predicate<BillCategory> { !$0.isArchived },
            sortBy: [SortDescriptor(\.order)]
        ))) ?? []
        accounts = (try? context.fetch(FetchDescriptor<Account>(
            predicate: #Predicate<Account> { !$0.isArchived },
            sortBy: [SortDescriptor(\.order)]
        ))) ?? []
    }

    func category(named name: String, kind: RecordKind) -> BillCategory? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let pool = categories.filter { $0.kind == kind }
        return pool.first { $0.name == name }
            ?? pool.first { name.contains($0.name) || $0.name.contains(name) }
    }

    func account(mentionedIn text: String) -> Account? {
        let text = text.lowercased()
        guard !text.isEmpty else { return nil }
        if let direct = accounts.filter({ text.contains($0.name.lowercased()) }).max(by: { $0.name.count < $1.name.count }) {
            return direct
        }
        let aliases: [(String, [String])] = [
            ("微信", ["wx", "微信支付", "vx"]),
            ("支付宝", ["zfb", "花呗", "余额宝"]),
            ("信用卡", ["刷卡", "信用"]),
            ("现金", ["现金", "cash"]),
        ]
        for (name, words) in aliases where words.contains(where: { text.contains($0) }) {
            if let account = accounts.first(where: { $0.name.contains(name) }) { return account }
        }
        return nil
    }

    /// Learned memory first, then keyword rules.
    func guessCategory(for text: String, kind: RecordKind) -> BillCategory? {
        if let id = CategoryMemory.lookup(text), let learned = categories.first(where: { $0.uuid == id && $0.kind == kind }) {
            return learned
        }
        let pool = categories.filter { $0.kind == kind }
        if let named = pool.first(where: { text.contains($0.name) }) { return named }
        let lowered = text.lowercased()
        for (categoryName, words) in Keywords.table(for: kind) where words.contains(where: { lowered.contains($0) }) {
            if let category = pool.first(where: { $0.name == categoryName }) { return category }
        }
        return nil
    }
}

enum Keywords {
    static let incomeHints = ["工资", "薪水", "收入", "奖金", "收到", "到账", "退款", "报销款", "分红", "利息", "转入", "收款", "兼职费", "稿费"]

    static func table(for kind: RecordKind) -> [(String, [String])] {
        kind == .income ? income : expense
    }

    static let expense: [(String, [String])] = [
        ("零食", ["咖啡", "奶茶", "瑞幸", "星巴克", "喜茶", "蜜雪", "零食", "水果", "饮料", "甜品", "蛋糕", "面包"]),
        ("餐饮", ["早餐", "早饭", "午饭", "午餐", "晚饭", "晚餐", "夜宵", "外卖", "美团", "饿了么", "火锅", "烧烤", "食堂", "吃饭", "餐厅", "麦当劳", "肯德基", "饭"]),
        ("交通", ["打车", "滴滴", "地铁", "公交", "高铁", "火车", "加油", "停车", "出租", "过路费", "单车", "uber"]),
        ("旅行", ["酒店", "机票", "旅游", "门票", "民宿", "航班", "携程"]),
        ("日用", ["超市", "日用", "纸巾", "洗发", "牙膏", "便利店", "盒马", "山姆", "711", "全家"]),
        ("服饰", ["衣服", "鞋", "裤", "外套", "裙", "t恤", "优衣库"]),
        ("购物", ["淘宝", "京东", "拼多多", "天猫", "购物", "网购"]),
        ("住房", ["房租", "物业", "房贷", "租金"]),
        ("水电", ["水费", "电费", "燃气", "煤气", "暖气"]),
        ("通讯", ["话费", "流量", "宽带", "充值"]),
        ("娱乐", ["电影", "游戏", "ktv", "演唱会", "剧本杀", "桌游", "酒吧"]),
        ("美容", ["理发", "剪发", "化妆", "美甲", "护肤", "口红"]),
        ("医疗", ["医院", "药", "看病", "挂号", "体检", "牙"]),
        ("教育", ["书", "课程", "培训", "学费", "网课", "考试"]),
        ("运动", ["健身", "游泳", "瑜伽", "球", "跑步"]),
        ("数码", ["手机", "电脑", "耳机", "充电", "数码", "ipad", "apple"]),
        ("宠物", ["猫", "狗", "宠物", "猫粮", "狗粮"]),
        ("人情", ["红包", "礼物", "份子", "请客", "随礼"]),
        ("订阅", ["会员", "订阅", "icloud", "netflix", "spotify", "chatgpt", "claude", "爱奇艺", "腾讯视频", "b站"]),
    ]

    static let income: [(String, [String])] = [
        ("工资", ["工资", "薪水", "月薪"]),
        ("奖金", ["奖金", "年终", "绩效"]),
        ("理财", ["理财", "利息", "分红", "基金", "股票", "收益"]),
        ("兼职", ["兼职", "稿费", "外快", "副业"]),
        ("红包", ["红包"]),
        ("退款", ["退款", "退货", "返现"]),
    ]
}

// MARK: - Rule-based parser (works offline on every device)

@MainActor
enum RuleParser {
    static func parse(_ text: String, catalog: Catalog) -> [RecordDraft] {
        let separators = CharacterSet(charactersIn: "，,。；;\n、")
        var segments = text.components(separatedBy: separators).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if segments.isEmpty { segments = [text] }

        var drafts: [RecordDraft] = []
        var carryOffset = 0
        for segment in segments {
            if let offset = dayOffset(in: segment) { carryOffset = offset }
            let amounts = amounts(in: segment)
            guard let amount = amounts.first else { continue }
            var draft = RecordDraft()
            draft.cents = amount
            draft.kind = Keywords.incomeHints.contains(where: { segment.contains($0) }) ? .income : .expense
            draft.date = Calendar.current.date(byAdding: .day, value: carryOffset, to: .now) ?? .now
            draft.note = cleanNote(segment)
            draft.categoryID = catalog.guessCategory(for: segment, kind: draft.kind)?.uuid
            draft.accountID = catalog.account(mentionedIn: segment)?.uuid ?? catalog.account(mentionedIn: text)?.uuid
            drafts.append(draft)
        }
        return drafts
    }

    static func dayOffset(in text: String) -> Int? {
        if text.contains("大前天") { return -3 }
        if text.contains("前天") { return -2 }
        if text.contains("昨天") || text.contains("昨晚") || text.contains("昨日") { return -1 }
        if text.contains("今天") || text.contains("今晚") || text.contains("今早") { return 0 }
        return nil
    }

    /// Amounts in cents, e.g. "35", "¥12.5", "28块", "1.2万".
    static func amounts(in text: String) -> [Int] {
        let pattern = #"(?:[¥￥$]\s*)?(\d+(?:\.\d{1,2})?)\s*(万|w|千|k)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match -> Int? in
            guard let value = Double(ns.substring(with: match.range(at: 1))) else { return nil }
            var multiplier = 1.0
            if match.range(at: 2).location != NSNotFound {
                switch ns.substring(with: match.range(at: 2)).lowercased() {
                case "万", "w": multiplier = 10_000
                case "千", "k": multiplier = 1_000
                default: break
                }
            }
            let cents = Money.cents(value * multiplier)
            return cents > 0 ? cents : nil
        }
    }

    private static func cleanNote(_ text: String) -> String {
        var note = text
        let noise = ["大前天", "前天", "昨天", "昨晚", "昨日", "今天", "今晚", "今早", "花了", "花", "用了", "付了",
                     "块钱", "块", "元", "rmb", "¥", "￥", "用微信", "用支付宝", "微信付", "支付宝付", "刷卡"]
        if let regex = try? NSRegularExpression(pattern: #"\d+(\.\d{1,2})?\s*(万|w|千|k)?"#, options: [.caseInsensitive]) {
            note = regex.stringByReplacingMatches(in: note, range: NSRange(location: 0, length: (note as NSString).length), withTemplate: "")
        }
        for word in noise { note = note.replacingOccurrences(of: word, with: "") }
        return String(note.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).prefix(16))
    }
}

// MARK: - Payment screenshot parser

@MainActor
enum ScreenshotParser {
    static func parse(lines: [String], catalog: Catalog) -> RecordDraft? {
        guard !lines.isEmpty else { return nil }
        let joined = lines.joined(separator: " ")

        // Amount: prefer a standalone amount line ("-28.00", "¥28.00"), else "金额 28.00".
        let amountLine = #"^[-−+]?\s*[¥￥]?\s*\d{1,3}(,\d{3})*(\.\d{1,2})?$|^[-−+]?\s*[¥￥]?\s*\d+(\.\d{1,2})$"#
        var cents: Int?
        var amountIndex: Int?
        for (index, line) in lines.enumerated() {
            let compact = line.replacingOccurrences(of: " ", with: "")
            if compact.range(of: amountLine, options: .regularExpression) != nil {
                let digits = compact.filter { $0.isNumber || $0 == "." }
                if let value = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")), value > 0 {
                    cents = Money.cents(value)
                    amountIndex = index
                    break
                }
            }
        }
        if cents == nil {
            for line in lines where line.contains("金额") || line.contains("实付") || line.contains("合计") {
                if let first = RuleParser.amounts(in: line).first { cents = first; break }
            }
        }
        guard let cents else { return nil }

        // Merchant: an explicit label, else the line right above the amount.
        var merchant = ""
        let labels = ["商户全称", "商户名称", "收款方", "商户", "商品", "对方", "收款人", "交易对方"]
        outer: for (index, line) in lines.enumerated() {
            for label in labels where line.hasPrefix(label) || line.contains(label + "：") || line.contains(label + ":") {
                let rest = line
                    .replacingOccurrences(of: label, with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: ":： ").union(.whitespaces))
                merchant = rest.isEmpty && index + 1 < lines.count ? lines[index + 1] : rest
                break outer
            }
        }
        if merchant.isEmpty, let amountIndex, amountIndex > 0 {
            let candidate = lines[amountIndex - 1]
            let skip = ["支付成功", "付款成功", "交易成功", "完成", "账单详情", "当前状态"]
            if !skip.contains(where: { candidate.contains($0) }) { merchant = candidate }
        }

        var draft = RecordDraft()
        draft.cents = cents
        let incomeWords = ["收款成功", "已收款", "已存入", "收入", "转入", "退款成功"]
        draft.kind = incomeWords.contains(where: { joined.contains($0) }) ? .income : .expense
        draft.note = String(merchant.prefix(16))
        draft.categoryID = catalog.guessCategory(for: merchant + " " + joined, kind: draft.kind)?.uuid
        draft.accountID = catalog.account(mentionedIn: joined)?.uuid
        return draft
    }
}
