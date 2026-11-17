import ActivityKit
import Foundation
import Testing
@testable import MoonMoney

struct PetSnapshotTests {
    private func clock() -> (calendar: Calendar, now: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = DateComponents(calendar: calendar, year: 2026, month: 6, day: 15, hour: 15).date!
        return (calendar, now)
    }

    private func day(_ offset: Int, calendar: Calendar, now: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }

    private func facts(dates: [Date] = [], pressured: Bool = false, name: String = "", species: String = "rabbit",
                       today: Int = 1_200, month: Int = 30_000, budget: Int = 100_000, days: Int = 10) -> PetFacts {
        let clock = clock()
        return PetFacts(
            speciesRaw: species, customName: name, dates: dates,
            todayExpense: today, monthExpense: month, monthBudget: budget, remainingDays: days,
            currency: "CNY", budgetPressured: pressured, enabled: true,
            now: clock.now, calendar: clock.calendar
        )
    }

    @Test func eggUntilThereIsARecord() {
        let snapshot = PetSnapshotLogic.make(facts())
        #expect(snapshot.stage == .egg)
        #expect(snapshot.mood == .normal)
        #expect(snapshot.streak == 0)
        #expect(snapshot.xp == 0)
        #expect(snapshot.hint == "记下第一笔就能孵化")
        #expect(snapshot.name == "小月兔")
        #expect(snapshot.expression == .normal)
        #expect(snapshot.progress == 0)
    }

    @Test func unknownSpeciesFallsBackToTheRabbit() {
        let snapshot = PetSnapshotLogic.make(facts(species: "phoenix"))
        #expect(snapshot.species == .rabbit)
        #expect(snapshot.name == "小月兔")
    }

    @Test func customNameIsTrimmed() {
        let snapshot = PetSnapshotLogic.make(facts(dates: [clock().now], name: "  豆豆  ", species: "cat"))
        #expect(snapshot.name == "豆豆")
        #expect(snapshot.species == .cat)
    }

    @Test func streakIgnoresAGapAndFutureDates() {
        let clock = clock()
        let dates = [0, -1, -2, -5, 3].map { day($0, calendar: clock.calendar, now: clock.now) }
        let snapshot = PetSnapshotLogic.make(facts(dates: dates))
        #expect(snapshot.recordedDays == 4)
        #expect(snapshot.todayCount == 1)
        #expect(snapshot.streak == 3)
        #expect(snapshot.xp == 4 * 10 + 4 * 2 + 3 * 3)
        #expect(snapshot.stage == .baby)
        #expect(snapshot.mood == .happy)
        #expect(snapshot.expression == .happy)
        #expect(snapshot.hint.contains("连续 3 天"))
        #expect(snapshot.hint.contains("今日"))
    }

    @Test func twoRecordsOnTheSameDayCountTwiceTowardExperience() {
        let clock = clock()
        let dates = [clock.now, clock.now.addingTimeInterval(-3_600)]
        let snapshot = PetSnapshotLogic.make(facts(dates: dates))
        #expect(snapshot.recordedDays == 1)
        #expect(snapshot.todayCount == 2)
        #expect(snapshot.streak == 1)
        #expect(snapshot.xp == PetSnapshotLogic.xp(recordedDays: 1, recordCount: 2, streak: 1))
    }

    @Test func hungryWhenYesterdayWasRecordedButTodayIsEmpty() {
        let clock = clock()
        let dates = [-1, -2].map { day($0, calendar: clock.calendar, now: clock.now) }
        let snapshot = PetSnapshotLogic.make(facts(dates: dates))
        #expect(snapshot.streak == 2)
        #expect(snapshot.todayCount == 0)
        #expect(snapshot.mood == .hungry)
        #expect(snapshot.hint == "今天还没记账")
        #expect(snapshot.expression == .normal)
    }

    @Test func sleepBeatsABudgetWarning() {
        let clock = clock()
        let snapshot = PetSnapshotLogic.make(facts(dates: [day(-3, calendar: clock.calendar, now: clock.now)], pressured: true))
        #expect(snapshot.mood == .sleepy)
        #expect(snapshot.streak == 0)
        #expect(snapshot.hint.contains("它睡着了"))
        #expect(snapshot.expression == .sleep)
    }

    @Test func budgetWorryBeatsAHappyDay() {
        let snapshot = PetSnapshotLogic.make(facts(dates: [clock().now], pressured: true))
        #expect(snapshot.mood == .worried)
        #expect(snapshot.hint.contains("注意预算"))
        #expect(snapshot.expression == .normal)
    }

    @Test func stageThresholdsAndProgress() {
        #expect(PetSnapshotLogic.stage(xp: 10_000, hasRecords: false) == .egg)
        #expect(PetSnapshotLogic.stage(xp: 0, hasRecords: true) == .baby)
        #expect(PetSnapshotLogic.stage(xp: 149, hasRecords: true) == .baby)
        #expect(PetSnapshotLogic.stage(xp: 150, hasRecords: true) == .teen)
        #expect(PetSnapshotLogic.stage(xp: 499, hasRecords: true) == .teen)
        #expect(PetSnapshotLogic.stage(xp: 500, hasRecords: true) == .adult)
        #expect(PetSnapshotLogic.progress(xp: 500, stage: .adult) == 1)
        let baby = PetSnapshotLogic.progress(xp: 15, stage: .baby)
        #expect(abs(baby - (14.0 / 149.0)) < 0.000_001)
        #expect(PetSnapshotLogic.xp(recordedDays: 1, recordCount: 5_000, streak: 100) == 10 + 2_000 * 2 + 60 * 3)
    }

    @Test func dailyAllowanceAndSpendingLine() {
        #expect(PetSnapshotLogic.dailyBudget(monthBudget: 0, monthExpense: 100, remainingDays: 4) == 0)
        #expect(PetSnapshotLogic.dailyBudget(monthBudget: 10_000, monthExpense: 2_500, remainingDays: 5) == 1_500)
        #expect(PetSnapshotLogic.dailyBudget(monthBudget: 10_000, monthExpense: 12_000, remainingDays: 4) == -500)
        #expect(PetSnapshotLogic.dailyBudget(monthBudget: 10_000, monthExpense: 100, remainingDays: 0) == 0)

        let open = PetCopy.spendingLine(todayExpense: 100, monthBudget: 0, dailyBudget: 0, currency: "CNY")
        #expect(open.contains("今日"))
        #expect(!open.contains("每天还可"))
        #expect(PetCopy.spendingLine(todayExpense: 100, monthBudget: 500, dailyBudget: 20, currency: "CNY").contains("每天还可"))
        #expect(PetCopy.spendingLine(todayExpense: 100, monthBudget: 500, dailyBudget: -10, currency: "CNY").contains("已超支"))
    }

    @Test func sessionEndsAtTheNextMidnight() {
        let clock = clock()
        let end = PetSnapshotLogic.endOfDay(for: clock.now, calendar: clock.calendar)
        let midnight = DateComponents(calendar: clock.calendar, year: 2026, month: 6, day: 16).date!
        #expect(end == midnight)
        #expect(PetSnapshotLogic.sessionIsActive(endsAt: end, now: end.addingTimeInterval(-1)))
        #expect(!PetSnapshotLogic.sessionIsActive(endsAt: end, now: end))
        #expect(!PetSnapshotLogic.sessionIsActive(endsAt: nil, now: clock.now))
    }

    @Test func snapshotRoundTripAndFreshness() throws {
        let original = PetSnapshotLogic.make(facts(dates: [clock().now], name: "豆豆", species: "dragon"))
        let decoded = try #require(PetSnapshotCoding.snapshot(from: PetSnapshotCoding.data(for: original)))
        #expect(decoded.species == .dragon)
        #expect(decoded.name == "豆豆")
        #expect(decoded.stage == original.stage)
        #expect(decoded.mood == original.mood)
        #expect(decoded.xp == original.xp)
        #expect(decoded.hint == original.hint)
        #expect(decoded.dailyBudget == original.dailyBudget)
        #expect(abs(decoded.progress - original.progress) < 0.000_001)
        #expect(abs(decoded.updatedAt.timeIntervalSince(original.updatedAt)) < 0.001)
        #expect(PetSnapshotCoding.snapshot(from: Data("nope".utf8)) == nil)

        var later = original
        later.updatedAt = original.updatedAt.addingTimeInterval(30)
        #expect(later.matches(original))
        #expect(later != original)
        later.streak += 1
        #expect(!later.matches(original))
    }

    @Test func emptyCaptureDoesNotHideAPublishedPet() {
        let clock = clock()
        let egg = PetSnapshotLogic.make(PetFacts(now: clock.now, calendar: clock.calendar))
        var grown = egg
        grown.recordedDays = 4
        grown.xp = 57
        #expect(PetStateStore.choose(captured: egg, stored: grown).recordedDays == 4)
        #expect(PetStateStore.choose(captured: grown, stored: egg).xp == 57)
        #expect(PetStateStore.choose(captured: egg, stored: nil).stage == .egg)
    }

    @Test func liveActivityStateCopiesTheSnapshot() {
        let snapshot = PetSnapshotLogic.make(facts(dates: [clock().now], pressured: true, species: "dragon"))
        let state = BookkeepingAttributes.ContentState(snapshot)
        #expect(state.species == .dragon)
        #expect(state.stage == snapshot.stage)
        #expect(state.mood == .worried)
        #expect(state.todayExpense == snapshot.todayExpense)
        #expect(state.dailyBudget == snapshot.dailyBudget)
        #expect(state.monthBudget == snapshot.monthBudget)
        #expect(state.hint == snapshot.hint)
        #expect(state.spendingLine == snapshot.spendingLine)
        #expect(state.streak == snapshot.streak)
    }
}

@MainActor
struct PetSnapshotStoreTests {
    @Test func eightyPercentBudgetWorriesThePet() throws {
        let context = try makeTestContext()
        let ledger = AppSettings.shared.currentLedgerID
        context.insert(Budget(amountCents: 1_000, ledgerID: ledger))
        context.insert(Record(kind: .expense, amountCents: 800, date: .now, ledgerID: ledger))
        try context.save()
        let snapshot = PetSnapshotLogic.capture(context: context)
        #expect(snapshot.mood == .worried)
        #expect(snapshot.todayExpense == 800)
        #expect(snapshot.todayCount == 1)
        #expect(snapshot.stage == .baby)
    }

    @Test func engineMatchesTheSharedSnapshot() throws {
        let context = try makeTestContext()
        let calendar = Calendar.current
        for offset in [0, 1, 2, 5] {
            let date = try #require(calendar.date(byAdding: .day, value: -offset, to: .now))
            context.insert(Record(kind: .expense, amountCents: 100, date: date))
        }
        try context.save()
        let status = PetEngine.compute(context: context)
        let snapshot = PetSnapshotLogic.capture(context: context)
        #expect(snapshot.stage == status.stage)
        #expect(snapshot.mood == status.mood)
        #expect(snapshot.streak == status.streak)
        #expect(snapshot.xp == status.xp)
        #expect(snapshot.recordedDays == status.recordedDays)
        #expect(snapshot.todayCount == status.todayCount)
        #expect(abs(snapshot.progress - status.progress) < 0.000_001)
    }
}
