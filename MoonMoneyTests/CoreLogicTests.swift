import Foundation
import SwiftData
import Testing
@testable import MoonMoney

// MARK: - Calculator & keypad

struct CalculatorTests {
    @Test func precedence() {
        #expect(Calculator.evaluate("12.5+3×2") == Decimal(string: "18.5"))
        #expect(Calculator.evaluate("10−4÷2") == 8)
        #expect(Calculator.evaluate("2×3×4") == 24)
    }

    @Test func edgeCases() {
        #expect(Calculator.evaluate("8÷0") == nil)
        #expect(Calculator.evaluate("5+") == 5, "trailing operator is ignored")
        #expect(Calculator.evaluate("") == 0)
    }

    @Test func keypadLimitsDecimals() {
        var input = KeypadInput()
        for key in ["1", ".", "2", "3", "4"] { input.type(key) }
        #expect(input.expression == "1.23")
        input.type("+")
        input.type("×")
        #expect(input.expression == "1.23×", "a second operator replaces the first")
        input.type("2")
        #expect(input.cents == 246)
        input.commit()
        #expect(input.expression == "2.46")
    }

    @Test func keypadLeadingZero() {
        var input = KeypadInput()
        input.type("0")
        input.type("5")
        #expect(input.expression == "5")
        input.clear()
        input.type(".")
        #expect(input.expression == "0.")
    }
}

// MARK: - Money

struct MoneyTests {
    @Test func centsRounding() {
        #expect(Money.cents(Decimal(string: "12.345")!) == 1235)
        #expect(Money.cents(19.99) == 1999)
    }

    @Test func compactFormatting() {
        #expect(Money.compact(1_200_000) == "1.2万")
        #expect(Money.compact(86_000) == "860")
        #expect(Money.compact(-150) == "-1.5")
    }
}

// MARK: - Periods (custom month start)

@Suite(.serialized)
struct PeriodTests {
    @Test func customMonthStart() throws {
        let settings = AppSettings.shared
        let saved = settings.monthStartDay
        defer { settings.monthStartDay = saved }
        settings.monthStartDay = 10

        let cal = Calendar.current
        let date = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12)))
        let interval = Periods.month(containing: date)
        #expect(cal.component(.month, from: interval.start) == 10)
        #expect(cal.component(.day, from: interval.start) == 10)
        #expect(cal.component(.month, from: interval.end) == 11)
        #expect(cal.component(.day, from: interval.end) == 10)
        #expect(Periods.totalDays(in: interval) == 31)
    }

    @Test func shiftKeepsAlignment() throws {
        let settings = AppSettings.shared
        let saved = settings.monthStartDay
        defer { settings.monthStartDay = saved }
        settings.monthStartDay = 1

        let cal = Calendar.current
        let date = try #require(cal.date(from: DateComponents(year: 2026, month: 3, day: 31)))
        let next = Periods.shift(Periods.month(containing: date), kind: .month, by: 1)
        #expect(cal.component(.month, from: next.start) == 4)
        #expect(cal.component(.day, from: next.start) == 1)
    }
}

// MARK: - CSV

struct CSVTests {
    @Test func quotedFields() {
        let rows = CSVService.parse("日期,备注\n2026-11-01,\"午饭, 和同事\"\n2026-11-02,\"他说\"\"好\"\"\"\n")
        #expect(rows.count == 3)
        #expect(rows[1][1] == "午饭, 和同事")
        #expect(rows[2][1] == "他说\"好\"")
    }

    @Test func multilineField() {
        let rows = CSVService.parse("a,b\n1,\"第一行\n第二行\"\n")
        #expect(rows.count == 2)
        #expect(rows[1][1] == "第一行\n第二行")
    }
}

// MARK: - In-memory store helpers

@MainActor
func makeTestContext() throws -> ModelContext {
    let schema = Schema(AppSchema.models)
    let config = ModelConfiguration("Test", schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: config)
    let context = ModelContext(container)
    Seed.insertCategories(into: context)
    Seed.insertAccounts(into: context)
    try context.save()
    return context
}

// MARK: - Smart parsing

@MainActor
struct RuleParserTests {
    @Test func amounts() {
        #expect(RuleParser.amounts(in: "打车 18") == [1800])
        #expect(RuleParser.amounts(in: "奖金1.2万") == [1_200_000])
        #expect(RuleParser.amounts(in: "¥12.5") == [1250])
    }

    @Test func relativeDays() {
        #expect(RuleParser.dayOffset(in: "昨天晚饭") == -1)
        #expect(RuleParser.dayOffset(in: "前天") == -2)
        #expect(RuleParser.dayOffset(in: "午饭") == nil)
    }

    @Test func splitsSentenceIntoRecords() throws {
        let context = try makeTestContext()
        let catalog = Catalog(context: context)
        let drafts = RuleParser.parse("午饭 32，打车 18 用微信", catalog: catalog)
        #expect(drafts.count == 2)
        #expect(drafts[0].cents == 3200)
        #expect(catalog.categories.first { $0.uuid == drafts[0].categoryID }?.name == "餐饮")
        #expect(catalog.categories.first { $0.uuid == drafts[1].categoryID }?.name == "交通")
        #expect(catalog.accounts.first { $0.uuid == drafts[1].accountID }?.name == "微信")
        #expect(!drafts[1].note.contains("微信"))
    }

    @Test func detectsIncome() throws {
        let context = try makeTestContext()
        let drafts = RuleParser.parse("今天发工资 18500", catalog: Catalog(context: context))
        #expect(drafts.first?.kind == .income)
        #expect(drafts.first?.cents == 1_850_000)
    }

    @Test func screenshotParser() throws {
        let context = try makeTestContext()
        let lines = ["支付成功", "瑞幸咖啡", "-15.00", "支付方式", "微信零钱"]
        let draft = ScreenshotParser.parse(lines: lines, catalog: Catalog(context: context))
        #expect(draft?.cents == 1500)
        #expect(draft?.note == "瑞幸咖啡")
        #expect(draft?.kind == .expense)
    }
}

// MARK: - Balances & budgets

@MainActor
struct LedgerMathTests {
    @Test func balanceSeriesMatchesPointQueries() throws {
        let context = try makeTestContext()
        let account = try #require(Catalog(context: context).accounts.first)
        account.initialBalanceCents = 10_000
        let cal = Calendar.current
        for day in 0..<10 {
            let date = try #require(cal.date(byAdding: .day, value: -day, to: .now))
            context.insert(Record(kind: day.isMultiple(of: 3) ? .income : .expense, amountCents: 500 + day * 10,
                                  date: date, account: account))
        }
        try context.save()
        let cutoffs = (0..<10).compactMap { cal.date(byAdding: .day, value: -$0, to: .now) }.sorted()
        let series = account.balanceSeries(at: cutoffs)
        for (cutoff, value) in zip(cutoffs, series) {
            #expect(value == account.balanceCents(asOf: cutoff))
        }
        #expect(series.last == account.balanceCents)
    }

    @Test func budgetLevels() throws {
        let context = try makeTestContext()
        let food = try #require(Catalog(context: context).categories.first { $0.name == "餐饮" })
        let interval = Periods.month(containing: .now)
        let budget = Budget(amountCents: 10_000, ledgerID: nil, category: food)
        context.insert(budget)
        let record = Record(kind: .expense, amountCents: 9_500, date: .now, category: food)
        context.insert(record)
        try context.save()

        let status = try #require(BudgetMonitor.statuses(budgets: [budget], records: [record], interval: interval).first)
        #expect(status.spent == 9_500)
        #expect(status.level >= .warning)
        #expect(status.remaining == 500)

        record.amountCents = 12_000
        let over = try #require(BudgetMonitor.statuses(budgets: [budget], records: [record], interval: interval).first)
        #expect(over.level == .over)
        #expect(over.headline.contains("超支"))
    }

    @Test func backupExportContainsEverything() throws {
        let context = try makeTestContext()
        let food = try #require(Catalog(context: context).categories.first)
        context.insert(Record(kind: .expense, amountCents: 1234, note: "测试", category: food))
        context.insert(SavingsGoal(name: "旅行", targetCents: 100_000))
        try context.save()

        let url = try BackupService.export(context: context)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupService.Backup.self, from: Data(contentsOf: url))
        #expect(backup.records.count == 1)
        #expect(backup.records.first?.amountCents == 1234)
        #expect(backup.records.first?.categoryID == food.uuid)
        #expect(backup.goals.first?.name == "旅行")
        #expect(backup.categories.count == Seed.expense.count + Seed.income.count)
    }
}
