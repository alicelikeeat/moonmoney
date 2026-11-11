import Foundation
import SwiftData

@MainActor
enum DataStore {
    /// Shared container used by the app and by App Intents (Siri / Shortcuts).
    static let container: ModelContainer = AppGroup.makeContainer(cloudSync: true)

    static var context: ModelContext { container.mainContext }

    /// Seeds default data on first launch and makes sure a ledger is selected.
    static func bootstrap() {
        let context = self.context
        let settings = AppSettings.shared

        // Decide from the data itself, not a flag: a flag can survive while the store is new
        // (reinstall, App Group move, restored backup), which used to leave categories empty.
        let categoryCount = (try? context.fetchCount(FetchDescriptor<BillCategory>())) ?? 0
        let accountCount = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        if categoryCount == 0 { Seed.insertCategories(into: context) }
        if accountCount == 0 { Seed.insertAccounts(into: context) }
        if !settings.hasSeeded {
            let tagCount = (try? context.fetchCount(FetchDescriptor<RecordTag>())) ?? 0
            if tagCount == 0 { Seed.insertTags(into: context) }
            settings.hasSeeded = true
        }
        repairUncategorized(context)

        let ledgers = (try? context.fetch(FetchDescriptor<Ledger>(sortBy: [SortDescriptor(\.order)]))) ?? []
        if ledgers.isEmpty {
            let ledger = Ledger(name: "日常账本")
            context.insert(ledger)
            settings.currentLedgerID = ledger.uuid
        } else if !ledgers.contains(where: { $0.uuid == settings.currentLedgerID }) {
            settings.currentLedgerID = ledgers.first?.uuid
        }

        RecurringEngine.run(in: context)
        try? context.save()
        AppServices.afterLaunch(context: context)
    }

    /// Records saved while categories were missing get a best guess from their note.
    private static func repairUncategorized(_ context: ModelContext) {
        let descriptor = FetchDescriptor<Record>(predicate: #Predicate<Record> { $0.category == nil && $0.kindRaw != 2 })
        guard let orphans = try? context.fetch(descriptor), !orphans.isEmpty else { return }
        let catalog = Catalog(context: context)
        for record in orphans {
            record.category = catalog.guessCategory(for: record.note, kind: record.kind)
                ?? catalog.categories.first { $0.name == "其他" && $0.kind == record.kind }
                ?? catalog.categories.first { $0.kind == record.kind }
            if record.account == nil {
                record.account = catalog.account(mentionedIn: record.note) ?? defaultAccount(in: context)
                if let account = record.account { record.currencyCode = account.currencyCode }
            }
        }
    }

    // MARK: Lookups

    static func category(_ id: UUID?, in context: ModelContext) -> BillCategory? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<BillCategory>(predicate: #Predicate<BillCategory> { $0.uuid == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func account(_ id: UUID?, in context: ModelContext) -> Account? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.uuid == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func defaultAccount(in context: ModelContext) -> Account? {
        if let account = account(AppSettings.shared.defaultAccountID, in: context), !account.isArchived {
            return account
        }
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate<Account> { !$0.isArchived },
            sortBy: [SortDescriptor(\.order)]
        )
        return try? context.fetch(descriptor).first
    }
}

enum Seed {
    static let expense: [(String, String, String)] = [
        ("餐饮", "fork.knife", "#FF9F0A"),
        ("零食", "cup.and.saucer.fill", "#C7A36B"),
        ("交通", "tram.fill", "#0A84FF"),
        ("购物", "bag.fill", "#FF375F"),
        ("日用", "basket.fill", "#30D158"),
        ("住房", "house.fill", "#5E5CE6"),
        ("水电", "bolt.fill", "#FFD60A"),
        ("通讯", "antenna.radiowaves.left.and.right", "#64D2FF"),
        ("娱乐", "gamecontroller.fill", "#BF5AF2"),
        ("服饰", "tshirt.fill", "#FF6B6B"),
        ("美容", "sparkles", "#FF2D92"),
        ("医疗", "cross.case.fill", "#FF453A"),
        ("教育", "book.fill", "#00C7BE"),
        ("运动", "figure.run", "#34C759"),
        ("旅行", "airplane", "#0A84FF"),
        ("数码", "iphone.gen3", "#8E8E93"),
        ("宠物", "pawprint.fill", "#AC8E68"),
        ("人情", "gift.fill", "#FF375F"),
        ("订阅", "repeat.circle.fill", "#5E5CE6"),
        ("其他", "ellipsis.circle.fill", "#8E8E93"),
    ]

    static let income: [(String, String, String)] = [
        ("工资", "banknote.fill", "#30D158"),
        ("奖金", "star.fill", "#FFD60A"),
        ("理财", "chart.line.uptrend.xyaxis", "#FF9F0A"),
        ("兼职", "briefcase.fill", "#0A84FF"),
        ("红包", "envelope.fill", "#FF453A"),
        ("退款", "arrow.uturn.backward.circle.fill", "#64D2FF"),
        ("其他", "ellipsis.circle.fill", "#8E8E93"),
    ]

    static func insertDefaults(into context: ModelContext) {
        insertCategories(into: context)
        insertAccounts(into: context)
        insertTags(into: context)
    }

    static func insertCategories(into context: ModelContext) {
        for (index, item) in expense.enumerated() {
            context.insert(BillCategory(name: item.0, symbol: item.1, colorHex: item.2, kind: .expense, order: index))
        }
        for (index, item) in income.enumerated() {
            context.insert(BillCategory(name: item.0, symbol: item.1, colorHex: item.2, kind: .income, order: index))
        }
    }

    static func insertAccounts(into context: ModelContext) {
        let cash = Account(name: "现金", type: .cash, colorHex: "#30D158", order: 0)
        let card = Account(name: "储蓄卡", type: .debit, colorHex: "#0A84FF", order: 1)
        let alipay = Account(name: "支付宝", type: .wallet, symbol: "a.circle.fill", colorHex: "#1677FF", order: 2)
        let wechat = Account(name: "微信", type: .wallet, symbol: "message.fill", colorHex: "#07C160", order: 3)
        let credit = Account(name: "信用卡", type: .credit, colorHex: "#FF9F0A", order: 4)
        credit.creditLimitCents = 2_000_000
        for account in [cash, card, alipay, wechat, credit] { context.insert(account) }
        AppSettings.shared.defaultAccountID = alipay.uuid
    }

    static func insertTags(into context: ModelContext) {
        for (name, hex) in [("报销", "#64D2FF"), ("旅行", "#0A84FF"), ("必要", "#30D158"), ("冲动消费", "#FF453A")] {
            context.insert(RecordTag(name: name, colorHex: hex))
        }
    }

    /// Generates ~3 months of realistic sample data for demos.
    static func insertSampleRecords(into context: ModelContext) {
        let categories = (try? context.fetch(FetchDescriptor<BillCategory>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard !categories.isEmpty, !accounts.isEmpty else { return }
        let ledgerID = AppSettings.shared.currentLedgerID
        let expense = categories.filter { $0.kind == .expense }
        let income = categories.filter { $0.kind == .income }
        let cal = Calendar.current
        let notes = ["午饭", "咖啡", "地铁", "超市", "晚餐", "打车", "电影", "水果", "外卖", "奶茶", ""]
        var generator = SystemRandomNumberGenerator()

        for dayOffset in 0..<90 {
            guard let day = cal.date(byAdding: .day, value: -dayOffset, to: .now) else { continue }
            let count = Int.random(in: 1...4, using: &generator)
            for _ in 0..<count {
                guard let category = expense.randomElement(using: &generator),
                      let account = accounts.randomElement(using: &generator) else { continue }
                let hour = Int.random(in: 8...22, using: &generator)
                let date = cal.date(bySettingHour: hour, minute: Int.random(in: 0...59), second: 0, of: day) ?? day
                let base = ["住房", "数码", "旅行"].contains(category.name) ? 30_000 : 4_000
                let cents = Int.random(in: 500...base, using: &generator)
                let record = Record(kind: .expense, amountCents: cents, date: date,
                                    note: notes.randomElement(using: &generator) ?? "",
                                    category: category, account: account, ledgerID: ledgerID)
                context.insert(record)
            }
            if cal.component(.day, from: day) == 10, let salary = income.first, let account = accounts.first(where: { $0.type == .debit }) {
                context.insert(Record(kind: .income, amountCents: 1_850_000, date: day, note: "工资",
                                      category: salary, account: account, ledgerID: ledgerID))
            }
        }
        try? context.save()
    }
}
