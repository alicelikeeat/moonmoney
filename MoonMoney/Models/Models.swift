import Foundation
import SwiftData
import SwiftUI

// All models are CloudKit-compatible: every attribute has a default,
// every relationship is optional, and nothing uses unique constraints.
// Turning on the iCloud capability in Xcode is enough to enable sync.

// MARK: - Enums

enum RecordKind: Int, Codable, CaseIterable, Identifiable {
    case expense = 0
    case income = 1
    case transfer = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        case .transfer: "转账"
        }
    }

    var tint: Color {
        switch self {
        case .expense: .expense
        case .income: .income
        case .transfer: .transfer
        }
    }
}

enum AccountType: Int, Codable, CaseIterable, Identifiable {
    case cash = 0
    case debit = 1
    case credit = 2
    case wallet = 3
    case investment = 4
    case receivable = 5
    case liability = 6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .cash: "现金"
        case .debit: "储蓄卡"
        case .credit: "信用卡"
        case .wallet: "网络账户"
        case .investment: "投资理财"
        case .receivable: "应收款"
        case .liability: "贷款负债"
        }
    }

    var defaultSymbol: String {
        switch self {
        case .cash: "banknote"
        case .debit: "creditcard"
        case .credit: "creditcard.trianglebadge.exclamationmark"
        case .wallet: "iphone.gen3"
        case .investment: "chart.line.uptrend.xyaxis"
        case .receivable: "arrow.down.left.circle"
        case .liability: "building.columns"
        }
    }

    /// Credit cards and loans normally carry a negative balance.
    var isLiabilityLike: Bool { self == .credit || self == .liability }
}

enum RecurrenceFrequency: Int, Codable, CaseIterable, Identifiable {
    case daily = 0, weekly = 1, monthly = 2, yearly = 3
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .daily: "每天"
        case .weekly: "每周"
        case .monthly: "每月"
        case .yearly: "每年"
        }
    }
    var component: Calendar.Component {
        switch self {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
    }
}

// MARK: - Ledger

@Model
final class Ledger {
    var uuid: UUID = UUID()
    var name: String = ""
    var symbol: String = "book.closed"
    var colorHex: String = "#5E5CE6"
    var order: Int = 0
    var createdAt: Date = Date.now

    init(name: String, symbol: String = "book.closed", colorHex: String = "#5E5CE6", order: Int = 0) {
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.order = order
    }

    var color: Color { Color(hex: colorHex) }
}

// MARK: - Account

@Model
final class Account {
    var uuid: UUID = UUID()
    var name: String = ""
    var typeRaw: Int = 0
    var symbol: String = "creditcard"
    var colorHex: String = "#0A84FF"
    var currencyCode: String = "CNY"
    var initialBalanceCents: Int = 0
    var creditLimitCents: Int = 0
    /// Statement day for credit cards (1...28, 0 = not set).
    var billingDay: Int = 0
    /// Payment due day for credit cards (1...28, 0 = not set).
    var dueDay: Int = 0
    var includeInNetWorth: Bool = true
    var isArchived: Bool = false
    var note: String = ""
    var order: Int = 0
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Record.account)
    var records: [Record]? = []

    @Relationship(deleteRule: .nullify, inverse: \Record.toAccount)
    var incomingTransfers: [Record]? = []

    init(name: String, type: AccountType, symbol: String? = nil, colorHex: String = "#0A84FF",
         currencyCode: String = "CNY", initialBalanceCents: Int = 0, order: Int = 0) {
        self.name = name
        self.typeRaw = type.rawValue
        self.symbol = symbol ?? type.defaultSymbol
        self.colorHex = colorHex
        self.currencyCode = currencyCode
        self.initialBalanceCents = initialBalanceCents
        self.order = order
    }

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .cash }
        set { typeRaw = newValue.rawValue }
    }

    var color: Color { Color(hex: colorHex) }

    /// Balance in the account's own currency, in cents.
    var balanceCents: Int {
        var balance = initialBalanceCents
        for record in records ?? [] {
            switch record.kind {
            case .expense: balance -= record.amountCents
            case .income: balance += record.amountCents
            case .transfer: balance -= record.amountCents + record.feeCents
            }
        }
        for record in incomingTransfers ?? [] where record.kind == .transfer {
            balance += record.destinationAmountCents
        }
        return balance
    }

    /// Balance as of the end of a given date (used for balance trend charts).
    func balanceCents(asOf date: Date) -> Int {
        var balance = initialBalanceCents
        for record in records ?? [] where record.date <= date {
            switch record.kind {
            case .expense: balance -= record.amountCents
            case .income: balance += record.amountCents
            case .transfer: balance -= record.amountCents + record.feeCents
            }
        }
        for record in incomingTransfers ?? [] where record.kind == .transfer && record.date <= date {
            balance += record.destinationAmountCents
        }
        return balance
    }

    var availableCreditCents: Int {
        max(0, creditLimitCents + min(0, balanceCents))
    }

    /// Next occurrence of the due day, if configured.
    var nextDueDate: Date? {
        guard dueDay > 0 else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var comps = cal.dateComponents([.year, .month], from: today)
        comps.day = dueDay
        guard let thisMonth = cal.date(from: comps) else { return nil }
        if thisMonth >= today { return thisMonth }
        return cal.date(byAdding: .month, value: 1, to: thisMonth)
    }
}

// MARK: - Category

@Model
final class BillCategory {
    var uuid: UUID = UUID()
    var name: String = ""
    var symbol: String = "tag"
    var colorHex: String = "#FF9F0A"
    var kindRaw: Int = 0
    var order: Int = 0
    var isArchived: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \Record.category)
    var records: [Record]? = []

    @Relationship(deleteRule: .cascade, inverse: \Budget.category)
    var budgets: [Budget]? = []

    init(name: String, symbol: String, colorHex: String, kind: RecordKind, order: Int = 0) {
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.kindRaw = kind.rawValue
        self.order = order
    }

    var kind: RecordKind {
        get { RecordKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var color: Color { Color(hex: colorHex) }
}

// MARK: - Tag

@Model
final class RecordTag {
    var uuid: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#64D2FF"
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Record.tags)
    var records: [Record]? = []

    init(name: String, colorHex: String = "#64D2FF") {
        self.name = name
        self.colorHex = colorHex
    }

    var color: Color { Color(hex: colorHex) }
}

// MARK: - Record

@Model
final class Record {
    var uuid: UUID = UUID()
    var kindRaw: Int = 0
    /// Amount in the source account's currency, always positive, in cents.
    var amountCents: Int = 0
    /// For transfers: amount that arrives in the destination account (0 = same as amountCents).
    var toAmountCents: Int = 0
    /// For transfers: fee charged on the source account.
    var feeCents: Int = 0
    var currencyCode: String = "CNY"
    var date: Date = Date.now
    var note: String = ""
    var ledgerID: UUID?
    var excludedFromStats: Bool = false
    var isRecurringInstance: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Attribute(.externalStorage)
    var photo: Data?

    var category: BillCategory?
    var account: Account?
    var toAccount: Account?
    var tags: [RecordTag]? = []

    init(kind: RecordKind, amountCents: Int, date: Date = .now, note: String = "",
         category: BillCategory? = nil, account: Account? = nil, ledgerID: UUID? = nil) {
        self.kindRaw = kind.rawValue
        self.amountCents = amountCents
        self.date = date
        self.note = note
        self.category = category
        self.account = account
        self.ledgerID = ledgerID
        self.currencyCode = account?.currencyCode ?? AppSettings.shared.baseCurrency
    }

    var kind: RecordKind {
        get { RecordKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var destinationAmountCents: Int { toAmountCents > 0 ? toAmountCents : amountCents }

    /// Amount converted into the user's base currency, in cents.
    var baseAmountCents: Int {
        AppSettings.shared.convertToBase(amountCents, from: currencyCode)
    }

    /// Signed amount in base currency: expense negative, income positive, transfer 0.
    var signedBaseCents: Int {
        switch kind {
        case .expense: -baseAmountCents
        case .income: baseAmountCents
        case .transfer: 0
        }
    }

    var displayTitle: String {
        switch kind {
        case .transfer:
            let from = account?.name ?? "?"
            let to = toAccount?.name ?? "?"
            return "\(from) → \(to)"
        default:
            return category?.name ?? "未分类"
        }
    }

    var displaySymbol: String {
        kind == .transfer ? "arrow.left.arrow.right" : (category?.symbol ?? "questionmark")
    }

    var displayColor: Color {
        kind == .transfer ? .transfer : (category?.color ?? .gray)
    }

    var sortedTags: [RecordTag] {
        (tags ?? []).sorted { $0.name < $1.name }
    }
}

// MARK: - Budget

@Model
final class Budget {
    var uuid: UUID = UUID()
    /// Monthly limit in base currency cents.
    var amountCents: Int = 0
    var ledgerID: UUID?
    /// nil category = the ledger's overall monthly budget.
    var category: BillCategory?
    var createdAt: Date = Date.now

    init(amountCents: Int, ledgerID: UUID?, category: BillCategory? = nil) {
        self.amountCents = amountCents
        self.ledgerID = ledgerID
        self.category = category
    }
}

// MARK: - Recurring rule

@Model
final class RecurringRule {
    var uuid: UUID = UUID()
    var name: String = ""
    var kindRaw: Int = 0
    var amountCents: Int = 0
    var note: String = ""
    var frequencyRaw: Int = 2
    var interval: Int = 1
    var startDate: Date = Date.now
    var nextDate: Date = Date.now
    var endDate: Date?
    var isActive: Bool = true
    var ledgerID: UUID?
    var categoryID: UUID?
    var accountID: UUID?
    var toAccountID: UUID?
    var generatedCount: Int = 0
    var createdAt: Date = Date.now

    init(name: String, kind: RecordKind, amountCents: Int, frequency: RecurrenceFrequency, startDate: Date) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.amountCents = amountCents
        self.frequencyRaw = frequency.rawValue
        self.startDate = startDate
        self.nextDate = startDate
    }

    var kind: RecordKind {
        get { RecordKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var scheduleDescription: String {
        interval <= 1 ? frequency.title : "每\(interval)\(unitName)"
    }

    private var unitName: String {
        switch frequency {
        case .daily: "天"
        case .weekly: "周"
        case .monthly: "个月"
        case .yearly: "年"
        }
    }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        Ledger.self, Account.self, BillCategory.self, RecordTag.self,
        Record.self, Budget.self, RecurringRule.self,
    ]
}
