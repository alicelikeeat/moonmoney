import CoreSpotlight
import Foundation
import SwiftData
import WidgetKit

/// Full-fidelity backup (JSON) of every model plus key settings, and the
/// "erase everything" action.
@MainActor
enum BackupService {
    static let formatVersion = 1

    // MARK: DTOs

    struct Backup: Codable {
        var version: Int
        var exportedAt: Date
        var settings: SettingsDTO
        var ledgers: [LedgerDTO]
        var accounts: [AccountDTO]
        var categories: [CategoryDTO]
        var tags: [TagDTO]
        var records: [RecordDTO]
        var budgets: [BudgetDTO]
        var rules: [RuleDTO]
        var goals: [GoalDTO]
        var debts: [DebtDTO]
    }

    struct SettingsDTO: Codable {
        var baseCurrency: String
        var rates: [String: Double]
        var monthStartDay: Int
        var weekStartsOnMonday: Bool
        var members: [String]
        var currentLedgerID: UUID?
        var defaultAccountID: UUID?
    }

    struct LedgerDTO: Codable {
        var uuid: UUID; var name: String; var symbol: String; var colorHex: String
        var order: Int; var createdAt: Date; var iconImage: Data?
    }

    struct AccountDTO: Codable {
        var uuid: UUID; var name: String; var typeRaw: Int; var symbol: String; var colorHex: String
        var currencyCode: String; var initialBalanceCents: Int; var creditLimitCents: Int
        var billingDay: Int; var dueDay: Int; var includeInNetWorth: Bool; var isArchived: Bool
        var note: String; var order: Int; var createdAt: Date; var iconImage: Data?
    }

    struct CategoryDTO: Codable {
        var uuid: UUID; var name: String; var symbol: String; var colorHex: String
        var kindRaw: Int; var order: Int; var isArchived: Bool; var iconImage: Data?
    }

    struct TagDTO: Codable {
        var uuid: UUID; var name: String; var colorHex: String; var createdAt: Date
    }

    struct RecordDTO: Codable {
        var uuid: UUID; var kindRaw: Int; var amountCents: Int; var toAmountCents: Int; var feeCents: Int
        var currencyCode: String; var date: Date; var note: String; var ledgerID: UUID?
        var excludedFromStats: Bool; var isRecurringInstance: Bool; var createdAt: Date; var updatedAt: Date
        var member: String; var reimbursementRaw: Int
        var installmentGroup: UUID?; var installmentIndex: Int; var installmentCount: Int
        var photo: Data?
        var categoryID: UUID?; var accountID: UUID?; var toAccountID: UUID?; var tagIDs: [UUID]
    }

    struct BudgetDTO: Codable {
        var uuid: UUID; var amountCents: Int; var ledgerID: UUID?; var categoryID: UUID?; var createdAt: Date
    }

    struct RuleDTO: Codable {
        var uuid: UUID; var name: String; var kindRaw: Int; var amountCents: Int; var note: String
        var frequencyRaw: Int; var interval: Int; var startDate: Date; var nextDate: Date; var endDate: Date?
        var isActive: Bool; var ledgerID: UUID?; var categoryID: UUID?; var accountID: UUID?; var toAccountID: UUID?
        var generatedCount: Int; var createdAt: Date
    }

    struct GoalDTO: Codable {
        var uuid: UUID; var name: String; var symbol: String; var colorHex: String
        var targetCents: Int; var savedCents: Int; var deadline: Date?; var accountID: UUID?
        var isArchived: Bool; var order: Int; var createdAt: Date
    }

    struct DebtDTO: Codable {
        var uuid: UUID; var directionRaw: Int; var person: String; var amountCents: Int; var repaidCents: Int
        var currencyCode: String; var date: Date; var dueDate: Date?; var note: String; var isSettled: Bool
        var createdAt: Date
    }

    struct Summary {
        var records = 0
        var accounts = 0
        var categories = 0
    }

    // MARK: Export

    static func export(context: ModelContext, includePhotos: Bool = true) throws -> URL {
        func all<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        let settings = AppSettings.shared

        let backup = Backup(
            version: formatVersion,
            exportedAt: .now,
            settings: SettingsDTO(
                baseCurrency: settings.baseCurrency, rates: settings.rates, monthStartDay: settings.monthStartDay,
                weekStartsOnMonday: settings.weekStartsOnMonday, members: settings.members,
                currentLedgerID: settings.currentLedgerID, defaultAccountID: settings.defaultAccountID
            ),
            ledgers: all(Ledger.self).map {
                LedgerDTO(uuid: $0.uuid, name: $0.name, symbol: $0.symbol, colorHex: $0.colorHex,
                          order: $0.order, createdAt: $0.createdAt, iconImage: $0.iconImage)
            },
            accounts: all(Account.self).map {
                AccountDTO(uuid: $0.uuid, name: $0.name, typeRaw: $0.typeRaw, symbol: $0.symbol, colorHex: $0.colorHex,
                           currencyCode: $0.currencyCode, initialBalanceCents: $0.initialBalanceCents,
                           creditLimitCents: $0.creditLimitCents, billingDay: $0.billingDay, dueDay: $0.dueDay,
                           includeInNetWorth: $0.includeInNetWorth, isArchived: $0.isArchived, note: $0.note,
                           order: $0.order, createdAt: $0.createdAt, iconImage: $0.iconImage)
            },
            categories: all(BillCategory.self).map {
                CategoryDTO(uuid: $0.uuid, name: $0.name, symbol: $0.symbol, colorHex: $0.colorHex,
                            kindRaw: $0.kindRaw, order: $0.order, isArchived: $0.isArchived, iconImage: $0.iconImage)
            },
            tags: all(RecordTag.self).map {
                TagDTO(uuid: $0.uuid, name: $0.name, colorHex: $0.colorHex, createdAt: $0.createdAt)
            },
            records: all(Record.self).map {
                RecordDTO(uuid: $0.uuid, kindRaw: $0.kindRaw, amountCents: $0.amountCents, toAmountCents: $0.toAmountCents,
                          feeCents: $0.feeCents, currencyCode: $0.currencyCode, date: $0.date, note: $0.note,
                          ledgerID: $0.ledgerID, excludedFromStats: $0.excludedFromStats,
                          isRecurringInstance: $0.isRecurringInstance, createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                          member: $0.member, reimbursementRaw: $0.reimbursementRaw,
                          installmentGroup: $0.installmentGroup, installmentIndex: $0.installmentIndex,
                          installmentCount: $0.installmentCount, photo: includePhotos ? $0.photo : nil,
                          categoryID: $0.category?.uuid, accountID: $0.account?.uuid, toAccountID: $0.toAccount?.uuid,
                          tagIDs: ($0.tags ?? []).map(\.uuid))
            },
            budgets: all(Budget.self).map {
                BudgetDTO(uuid: $0.uuid, amountCents: $0.amountCents, ledgerID: $0.ledgerID,
                          categoryID: $0.category?.uuid, createdAt: $0.createdAt)
            },
            rules: all(RecurringRule.self).map {
                RuleDTO(uuid: $0.uuid, name: $0.name, kindRaw: $0.kindRaw, amountCents: $0.amountCents, note: $0.note,
                        frequencyRaw: $0.frequencyRaw, interval: $0.interval, startDate: $0.startDate,
                        nextDate: $0.nextDate, endDate: $0.endDate, isActive: $0.isActive, ledgerID: $0.ledgerID,
                        categoryID: $0.categoryID, accountID: $0.accountID, toAccountID: $0.toAccountID,
                        generatedCount: $0.generatedCount, createdAt: $0.createdAt)
            },
            goals: all(SavingsGoal.self).map {
                GoalDTO(uuid: $0.uuid, name: $0.name, symbol: $0.symbol, colorHex: $0.colorHex,
                        targetCents: $0.targetCents, savedCents: $0.savedCents, deadline: $0.deadline,
                        accountID: $0.accountID, isArchived: $0.isArchived, order: $0.order, createdAt: $0.createdAt)
            },
            debts: all(Debt.self).map {
                DebtDTO(uuid: $0.uuid, directionRaw: $0.directionRaw, person: $0.person, amountCents: $0.amountCents,
                        repaidCents: $0.repaidCents, currencyCode: $0.currencyCode, date: $0.date, dueDate: $0.dueDate,
                        note: $0.note, isSettled: $0.isSettled, createdAt: $0.createdAt)
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(backup)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let stamp = formatter.string(from: .now)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MoonMoney-备份-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: Restore

    /// Replaces all current data with the backup's contents.
    static func restore(from url: URL, context: ModelContext) throws -> Summary {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: Data(contentsOf: url))

        try deleteEverything(context: context)

        var ledgers: [UUID: Ledger] = [:]
        for dto in backup.ledgers {
            let ledger = Ledger(name: dto.name, symbol: dto.symbol, colorHex: dto.colorHex, order: dto.order)
            ledger.uuid = dto.uuid; ledger.createdAt = dto.createdAt; ledger.iconImage = dto.iconImage
            context.insert(ledger); ledgers[dto.uuid] = ledger
        }
        var accounts: [UUID: Account] = [:]
        for dto in backup.accounts {
            let account = Account(name: dto.name, type: AccountType(rawValue: dto.typeRaw) ?? .cash, symbol: dto.symbol,
                                  colorHex: dto.colorHex, currencyCode: dto.currencyCode,
                                  initialBalanceCents: dto.initialBalanceCents, order: dto.order)
            account.uuid = dto.uuid; account.creditLimitCents = dto.creditLimitCents
            account.billingDay = dto.billingDay; account.dueDay = dto.dueDay
            account.includeInNetWorth = dto.includeInNetWorth; account.isArchived = dto.isArchived
            account.note = dto.note; account.createdAt = dto.createdAt; account.iconImage = dto.iconImage
            context.insert(account); accounts[dto.uuid] = account
        }
        var categories: [UUID: BillCategory] = [:]
        for dto in backup.categories {
            let category = BillCategory(name: dto.name, symbol: dto.symbol, colorHex: dto.colorHex,
                                        kind: RecordKind(rawValue: dto.kindRaw) ?? .expense, order: dto.order)
            category.uuid = dto.uuid; category.isArchived = dto.isArchived; category.iconImage = dto.iconImage
            context.insert(category); categories[dto.uuid] = category
        }
        var tags: [UUID: RecordTag] = [:]
        for dto in backup.tags {
            let tag = RecordTag(name: dto.name, colorHex: dto.colorHex)
            tag.uuid = dto.uuid; tag.createdAt = dto.createdAt
            context.insert(tag); tags[dto.uuid] = tag
        }
        for dto in backup.records {
            let record = Record(kind: RecordKind(rawValue: dto.kindRaw) ?? .expense, amountCents: dto.amountCents,
                                date: dto.date, note: dto.note,
                                category: dto.categoryID.flatMap { categories[$0] },
                                account: dto.accountID.flatMap { accounts[$0] }, ledgerID: dto.ledgerID)
            record.uuid = dto.uuid; record.toAmountCents = dto.toAmountCents; record.feeCents = dto.feeCents
            record.currencyCode = dto.currencyCode; record.excludedFromStats = dto.excludedFromStats
            record.isRecurringInstance = dto.isRecurringInstance; record.createdAt = dto.createdAt
            record.updatedAt = dto.updatedAt; record.member = dto.member; record.reimbursementRaw = dto.reimbursementRaw
            record.installmentGroup = dto.installmentGroup; record.installmentIndex = dto.installmentIndex
            record.installmentCount = dto.installmentCount; record.photo = dto.photo
            record.toAccount = dto.toAccountID.flatMap { accounts[$0] }
            record.tags = dto.tagIDs.compactMap { tags[$0] }
            context.insert(record)
        }
        for dto in backup.budgets {
            let budget = Budget(amountCents: dto.amountCents, ledgerID: dto.ledgerID,
                                category: dto.categoryID.flatMap { categories[$0] })
            budget.uuid = dto.uuid; budget.createdAt = dto.createdAt
            context.insert(budget)
        }
        for dto in backup.rules {
            let rule = RecurringRule(name: dto.name, kind: RecordKind(rawValue: dto.kindRaw) ?? .expense,
                                     amountCents: dto.amountCents,
                                     frequency: RecurrenceFrequency(rawValue: dto.frequencyRaw) ?? .monthly,
                                     startDate: dto.startDate)
            rule.uuid = dto.uuid; rule.note = dto.note; rule.interval = dto.interval; rule.nextDate = dto.nextDate
            rule.endDate = dto.endDate; rule.isActive = dto.isActive; rule.ledgerID = dto.ledgerID
            rule.categoryID = dto.categoryID; rule.accountID = dto.accountID; rule.toAccountID = dto.toAccountID
            rule.generatedCount = dto.generatedCount; rule.createdAt = dto.createdAt
            context.insert(rule)
        }
        for dto in backup.goals {
            let goal = SavingsGoal(name: dto.name, targetCents: dto.targetCents)
            goal.uuid = dto.uuid; goal.symbol = dto.symbol; goal.colorHex = dto.colorHex; goal.savedCents = dto.savedCents
            goal.deadline = dto.deadline; goal.accountID = dto.accountID; goal.isArchived = dto.isArchived
            goal.order = dto.order; goal.createdAt = dto.createdAt
            context.insert(goal)
        }
        for dto in backup.debts {
            let debt = Debt(lent: dto.directionRaw == 0, person: dto.person, amountCents: dto.amountCents)
            debt.uuid = dto.uuid; debt.repaidCents = dto.repaidCents; debt.currencyCode = dto.currencyCode
            debt.date = dto.date; debt.dueDate = dto.dueDate; debt.note = dto.note; debt.isSettled = dto.isSettled
            debt.createdAt = dto.createdAt
            context.insert(debt)
        }

        let settings = AppSettings.shared
        settings.baseCurrency = backup.settings.baseCurrency
        settings.rates = backup.settings.rates
        settings.monthStartDay = backup.settings.monthStartDay
        settings.weekStartsOnMonday = backup.settings.weekStartsOnMonday
        settings.members = backup.settings.members
        settings.currentLedgerID = backup.settings.currentLedgerID
        settings.defaultAccountID = backup.settings.defaultAccountID
        settings.hasSeeded = true

        try context.save()
        DataStore.bootstrap()
        WidgetCenter.shared.reloadAllTimelines()
        return Summary(records: backup.records.count, accounts: backup.accounts.count, categories: backup.categories.count)
    }

    // MARK: Erase

    /// Deletes every record, account, category, budget… then recreates the defaults.
    static func eraseAll(context: ModelContext, resetAppearance: Bool) throws {
        try deleteEverything(context: context)
        let settings = AppSettings.shared
        settings.currentLedgerID = nil
        settings.defaultAccountID = nil
        settings.members = []
        settings.hasSeeded = false
        if resetAppearance {
            BackgroundStore.shared.reset()
        }
        for key in AppGroup.defaults.dictionaryRepresentation().keys
        where key.hasPrefix("budgetAlert-") || key == "categoryMemory" {
            AppGroup.defaults.removeObject(forKey: key)
        }
        try context.save()
        DataStore.bootstrap()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func deleteEverything(context: ModelContext) throws {
        try context.delete(model: Record.self)
        try context.delete(model: Budget.self)
        try context.delete(model: RecurringRule.self)
        try context.delete(model: SavingsGoal.self)
        try context.delete(model: Debt.self)
        try context.delete(model: RecordTag.self)
        try context.delete(model: BillCategory.self)
        try context.delete(model: Account.self)
        try context.delete(model: Ledger.self)
        try context.save()
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [Spotlight.domain])
    }
}
