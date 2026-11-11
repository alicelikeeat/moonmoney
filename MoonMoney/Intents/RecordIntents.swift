import AppIntents
import Foundation
import SwiftData

// MARK: - Entities

struct CategoryEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "分类"
    static let defaultQuery = CategoryQuery()

    var id: UUID
    var name: String
    var symbol: String
    var kindTitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(kindTitle)",
            image: .init(systemName: symbol)
        )
    }

    init(_ category: BillCategory) {
        id = category.uuid
        name = category.name
        symbol = category.symbol
        kindTitle = category.kind.title
    }
}

struct CategoryQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [CategoryEntity] {
        all().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [CategoryEntity] {
        all()
    }

    @MainActor
    private func all() -> [CategoryEntity] {
        let descriptor = FetchDescriptor<BillCategory>(
            predicate: #Predicate<BillCategory> { !$0.isArchived },
            sortBy: [SortDescriptor(\.kindRaw), SortDescriptor(\.order)]
        )
        let categories = (try? DataStore.context.fetch(descriptor)) ?? []
        return categories.map(CategoryEntity.init)
    }
}

struct AccountEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "账户"
    static let defaultQuery = AccountQuery()

    var id: UUID
    var name: String
    var symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }
}

struct AccountQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [AccountEntity] {
        all()
    }

    @MainActor
    private func all() -> [AccountEntity] {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate<Account> { !$0.isArchived },
            sortBy: [SortDescriptor(\.order)]
        )
        let accounts = (try? DataStore.context.fetch(descriptor)) ?? []
        return accounts.map { AccountEntity(id: $0.uuid, name: $0.name, symbol: $0.symbol) }
    }
}

enum IntentRecordKind: String, AppEnum {
    case expense, income

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "类型"
    static let caseDisplayRepresentations: [IntentRecordKind: DisplayRepresentation] = [
        .expense: "支出",
        .income: "收入",
    ]

    var kind: RecordKind { self == .expense ? .expense : .income }
}

// MARK: - Intents

/// Adds a record without opening the app, e.g. "嘿 Siri，用 MoonMoney 记一笔".
struct AddRecordIntent: AppIntent {
    static let title: LocalizedStringResource = "记一笔"
    static let description = IntentDescription("快速添加一笔支出或收入。")

    @Parameter(title: "金额")
    var amount: Double

    @Parameter(title: "类型", default: .expense)
    var kind: IntentRecordKind

    @Parameter(title: "分类")
    var category: CategoryEntity?

    @Parameter(title: "账户")
    var account: AccountEntity?

    @Parameter(title: "备注")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("记录 \(\.$kind) \(\.$amount) 元") {
            \.$category
            \.$account
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = DataStore.context
        let recordKind = kind.kind
        var resolvedCategory = DataStore.category(category?.id, in: context)
        if resolvedCategory == nil {
            let kindRaw = recordKind.rawValue
            var descriptor = FetchDescriptor<BillCategory>(
                predicate: #Predicate<BillCategory> { $0.kindRaw == kindRaw && !$0.isArchived },
                sortBy: [SortDescriptor(\.order)]
            )
            descriptor.fetchLimit = 1
            resolvedCategory = try? context.fetch(descriptor).first
        }
        let resolvedAccount = DataStore.account(account?.id, in: context) ?? DataStore.defaultAccount(in: context)
        guard amount > 0 else {
            return .result(dialog: "金额需要大于 0")
        }
        let record = Record(
            kind: recordKind,
            amountCents: Money.cents(amount),
            note: note ?? "",
            category: resolvedCategory,
            account: resolvedAccount,
            ledgerID: AppSettings.shared.currentLedgerID
        )
        context.insert(record)
        try context.save()

        let text = "已记录\(recordKind.title) \(Money.format(record.amountCents, code: record.currencyCode))（\(resolvedCategory?.name ?? "未分类")）"
        return .result(dialog: "\(text)")
    }
}

/// Opens the app straight into the entry sheet.
struct OpenEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "打开记账面板"
    static let description = IntentDescription("打开 MoonMoney 并直接进入记一笔。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.tab = .home
        Router.shared.newRecord()
        return .result()
    }
}

/// Reports this month's spending, e.g. for a Siri question.
struct MonthSpendingIntent: AppIntent {
    static let title: LocalizedStringResource = "本月花了多少"
    static let description = IntentDescription("查询当前账本本月的支出与预算剩余。")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let interval = Periods.month(containing: .now)
        let start = interval.start
        let end = interval.end
        let ledgerID = AppSettings.shared.currentLedgerID
        let descriptor = FetchDescriptor<Record>(
            predicate: #Predicate<Record> { $0.date >= start && $0.date < end && $0.ledgerID == ledgerID }
        )
        let records = (try? DataStore.context.fetch(descriptor)) ?? []
        let summary = Stats.summary(records)

        let budgets = (try? DataStore.context.fetch(FetchDescriptor<Budget>())) ?? []
        let total = budgets.first { $0.ledgerID == ledgerID && $0.category == nil }

        var text = "本月已支出 \(Money.format(summary.expense))"
        if let total, total.amountCents > 0 {
            text += "，预算剩余 \(Money.format(total.amountCents - summary.expense))"
        }
        return .result(value: Double(summary.expense) / 100, dialog: "\(text)")
    }
}

struct MoonMoneyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddRecordIntent(),
            phrases: [
                "用\(.applicationName)记一笔",
                "在\(.applicationName)记账",
            ],
            shortTitle: "记一笔",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: OpenEntryIntent(),
            phrases: ["打开\(.applicationName)记账面板"],
            shortTitle: "打开记账",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: MonthSpendingIntent(),
            phrases: [
                "\(.applicationName)本月花了多少",
            ],
            shortTitle: "本月支出",
            systemImageName: "chart.pie.fill"
        )
    }
}
