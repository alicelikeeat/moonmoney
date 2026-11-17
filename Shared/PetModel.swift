import CoreGraphics
import Foundation
import SwiftData
import WidgetKit

// MARK: - Sprite geometry

struct PetCell { let row: Int; let col: Int }
struct PetFoot { let row: Int; let from: Int; let to: Int }
struct PetPaint { let row: Int; let col: Int; let code: Character }

struct PetSpriteSheet {
    let body: [String]
    let palette: [Character: String]
    let eyes: [PetCell]
    let mouth: PetCell
    let cheeks: [PetCell]
    let feetA: [PetFoot]
    let feetB: [PetFoot]
    let accessory: [PetPaint]
}

// MARK: - Species, stages, moods

enum PetSpecies: String, CaseIterable, Identifiable, Sendable {
    case rabbit, cat, dragon
    var id: String { rawValue }

    var defaultName: String {
        switch self {
        case .rabbit: "小月兔"
        case .cat: "招财猫"
        case .dragon: "小金龙"
        }
    }

    var sheet: PetSpriteSheet {
        switch self {
        case .rabbit: PetSprites.rabbit
        case .cat: PetSprites.cat
        case .dragon: PetSprites.dragon
        }
    }

    var catchphrases: [String] {
        switch self {
        case .rabbit: ["月亮上也要精打细算～", "胡萝卜要一根一根攒！", "今晚月色真美，钱包也是。"]
        case .cat: ["招财进宝，喵！", "小钱也是钱，喵～", "记账的人运气都不会差！"]
        case .dragon: ["龙的宝藏要一点点攒！", "嗷呜！今天也守住金库！", "等我长大，喷火保护你的预算！"]
        }
    }
}

enum PetStage: Int, Comparable, Sendable {
    case egg, baby, teen, adult
    static func < (lhs: PetStage, rhs: PetStage) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .egg: "蛋"
        case .baby: "幼年"
        case .teen: "少年"
        case .adult: "成年"
        }
    }

    /// Experience needed to reach this stage.
    var threshold: Int {
        switch self {
        case .egg: 0
        case .baby: 1
        case .teen: 150
        case .adult: 500
        }
    }

    var next: PetStage? {
        switch self {
        case .egg: .baby
        case .baby: .teen
        case .teen: .adult
        case .adult: nil
        }
    }

    var scale: CGFloat {
        switch self {
        case .egg, .adult: 1
        case .baby: 0.78
        case .teen: 0.9
        }
    }
}

enum PetMood: String, Sendable {
    case happy, normal, hungry, worried, sleepy

    var title: String {
        switch self {
        case .happy: "开心"
        case .normal: "平静"
        case .hungry: "有点饿"
        case .worried: "担心预算"
        case .sleepy: "睡着了"
        }
    }

    var symbol: String {
        switch self {
        case .happy: "heart.fill"
        case .normal: "face.smiling"
        case .hungry: "fork.knife"
        case .worried: "drop.fill"
        case .sleepy: "moon.zzz.fill"
        }
    }
}

enum PetExpression: String, Sendable {
    case normal, blink, happy, eat, sleep
}

enum PetLink {
    /// Opens the in-app pet page. Used by widgets and the Live Activity.
    static let page = URL(string: "moonmoney://pet")!
}

// MARK: - Snapshot

/// Inputs for the pure pet-state function. Dates drive growth; money fields drive the hint.
struct PetFacts: Sendable {
    var speciesRaw: String = "rabbit"
    var customName: String = ""
    var dates: [Date] = []
    var todayExpense: Int = 0
    var monthExpense: Int = 0
    var monthBudget: Int = 0
    var remainingDays: Int = 1
    var currency: String = "CNY"
    var budgetPressured = false
    var enabled = true
    var customPetID: String? = nil
    var now: Date = .now
    var calendar: Calendar = .current
}

/// Pet state shared with the widget extension through the App Group.
struct PetSnapshot: Codable, Equatable, Sendable {
    var speciesRaw: String
    var name: String
    var stageRaw: Int
    var moodRaw: String
    var expressionRaw: String
    var xp: Int
    var streak: Int
    var recordedDays: Int
    var todayCount: Int
    var todayExpense: Int
    var monthExpense: Int
    var monthBudget: Int
    /// What is left of the monthly budget divided by the days still in the month.
    /// Negative once the month is already over budget.
    var dailyBudget: Int
    var currency: String
    var hint: String
    var progress: Double
    var enabled: Bool
    /// Set when the user is showing a pet made from a photo. Nil uses the built-in species.
    var customPetID: String? = nil
    var updatedAt: Date

    var species: PetSpecies { PetSpecies(rawValue: speciesRaw) ?? .rabbit }
    var stage: PetStage { PetStage(rawValue: stageRaw) ?? .egg }
    var mood: PetMood { PetMood(rawValue: moodRaw) ?? .normal }
    var expression: PetExpression { PetExpression(rawValue: expressionRaw) ?? .normal }

    var spendingLine: String {
        PetCopy.spendingLine(todayExpense: todayExpense, monthBudget: monthBudget, dailyBudget: dailyBudget, currency: currency)
    }

    /// Same pet, ignoring the timestamp, so a timeline reload does not rewrite an unchanged snapshot.
    func matches(_ other: PetSnapshot) -> Bool {
        speciesRaw == other.speciesRaw && name == other.name && stageRaw == other.stageRaw
            && moodRaw == other.moodRaw && expressionRaw == other.expressionRaw
            && xp == other.xp && streak == other.streak && recordedDays == other.recordedDays
            && todayCount == other.todayCount && todayExpense == other.todayExpense
            && monthExpense == other.monthExpense && monthBudget == other.monthBudget
            && dailyBudget == other.dailyBudget && currency == other.currency
            && hint == other.hint && progress == other.progress && enabled == other.enabled
            && customPetID == other.customPetID
    }

    static var placeholder: PetSnapshot {
        PetSnapshotLogic.make(PetFacts(
            dates: [.now],
            todayExpense: 3_200,
            monthExpense: 86_000,
            monthBudget: 600_000,
            remainingDays: 12
        ))
    }
}

enum PetCopy {
    static func hint(stage: PetStage, mood: PetMood, todayExpense: Int, streak: Int, currency: String) -> String {
        if stage == .egg { return "记下第一笔就能孵化" }
        if mood == .hungry { return "今天还没记账" }
        let spend = "今日 \(Money.format(todayExpense, code: currency))"
        if mood == .sleepy { return "\(spend) · 它睡着了" }
        if mood == .worried { return "\(spend) · 注意预算" }
        if streak >= 2 { return "\(spend) · 连续 \(streak) 天" }
        return spend
    }

    static func spendingLine(todayExpense: Int, monthBudget: Int, dailyBudget: Int, currency: String) -> String {
        let spend = "今日 \(Money.format(todayExpense, code: currency))"
        guard monthBudget > 0 else { return spend }
        if dailyBudget < 0 { return "\(spend) · 已超支" }
        return "\(spend) · 每天还可 \(Money.format(dailyBudget, code: currency))"
    }
}

enum PetSnapshotLogic {
    static func xp(recordedDays: Int, recordCount: Int, streak: Int) -> Int {
        recordedDays * 10 + min(recordCount, 2_000) * 2 + min(streak, 60) * 3
    }

    static func stage(xp: Int, hasRecords: Bool) -> PetStage {
        if !hasRecords { return .egg }
        if xp >= PetStage.adult.threshold { return .adult }
        if xp >= PetStage.teen.threshold { return .teen }
        return .baby
    }

    static func progress(xp: Int, stage: PetStage) -> Double {
        guard let next = stage.next else { return 1 }
        let start = stage.threshold
        return Double(xp - start) / Double(max(1, next.threshold - start))
    }

    static func expression(stage: PetStage, mood: PetMood) -> PetExpression {
        if stage == .egg { return .normal }
        switch mood {
        case .happy: return .happy
        case .sleepy: return .sleep
        case .hungry, .worried, .normal: return .normal
        }
    }

    /// Consecutive recorded days ending today, or ending yesterday when today is still empty.
    static func habit(dates: [Date], now: Date, calendar: Calendar) -> (recordedDays: Int, todayCount: Int, streak: Int, daysSinceLast: Int?) {
        let past = dates.filter { $0 <= now }
        let days = Set(past.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)
        let todayCount = past.filter { calendar.isDate($0, inSameDayAs: today) }.count
        var streak = 0
        var cursor = days.contains(today) ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var guardrail = 0
        while days.contains(cursor), guardrail < 10_000 {
            streak += 1
            guardrail += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor), previous < cursor else { break }
            cursor = previous
        }
        let daysSinceLast = days.max().flatMap { calendar.dateComponents([.day], from: $0, to: today).day }
        return (days.count, todayCount, streak, daysSinceLast)
    }

    static func mood(stage: PetStage, todayCount: Int, daysSinceLast: Int?, budgetPressured: Bool) -> PetMood {
        if let daysSinceLast, daysSinceLast >= 2 { return .sleepy }
        if budgetPressured { return .worried }
        if todayCount == 0, stage != .egg { return .hungry }
        if todayCount > 0 { return .happy }
        return .normal
    }

    /// Remainder of the monthly budget spread across the days still left. Zero when there is no budget.
    static func dailyBudget(monthBudget: Int, monthExpense: Int, remainingDays: Int) -> Int {
        guard monthBudget > 0, remainingDays > 0 else { return 0 }
        return (monthBudget - monthExpense) / remainingDays
    }

    static func endOfDay(for date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    static func sessionIsActive(endsAt: Date?, now: Date) -> Bool {
        guard let endsAt else { return false }
        return now < endsAt
    }

    static func make(_ facts: PetFacts) -> PetSnapshot {
        let species = PetSpecies(rawValue: facts.speciesRaw) ?? .rabbit
        let trimmed = facts.customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let customID = facts.customPetID?.isEmpty == false ? facts.customPetID : nil
        let habit = habit(dates: facts.dates, now: facts.now, calendar: facts.calendar)
        let experience = xp(recordedDays: habit.recordedDays, recordCount: facts.dates.filter { $0 <= facts.now }.count, streak: habit.streak)
        let stage = stage(xp: experience, hasRecords: habit.recordedDays > 0)
        let mood = mood(stage: stage, todayCount: habit.todayCount, daysSinceLast: habit.daysSinceLast, budgetPressured: facts.budgetPressured)
        let expression = expression(stage: stage, mood: mood)
        return PetSnapshot(
            speciesRaw: species.rawValue,
            name: trimmed.isEmpty ? (customID == nil ? species.defaultName : "我的宠物") : trimmed,
            stageRaw: stage.rawValue,
            moodRaw: mood.rawValue,
            expressionRaw: expression.rawValue,
            xp: experience,
            streak: habit.streak,
            recordedDays: habit.recordedDays,
            todayCount: habit.todayCount,
            todayExpense: facts.todayExpense,
            monthExpense: facts.monthExpense,
            monthBudget: facts.monthBudget,
            dailyBudget: dailyBudget(monthBudget: facts.monthBudget, monthExpense: facts.monthExpense, remainingDays: facts.remainingDays),
            currency: facts.currency,
            hint: PetCopy.hint(stage: stage, mood: mood, todayExpense: facts.todayExpense, streak: habit.streak, currency: facts.currency),
            progress: progress(xp: experience, stage: stage),
            enabled: facts.enabled,
            customPetID: customID,
            updatedAt: facts.now
        )
    }

    /// Rebuilds the snapshot from the shared store. Safe to call from the app or the widget extension.
    static func capture(context: ModelContext, now: Date = .now) -> PetSnapshot {
        let settings = AppSettings.shared
        settings.reload()
        let calendar = Calendar.current
        let ledgerID = settings.currentLedgerID

        var habitFetch = FetchDescriptor<Record>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        habitFetch.propertiesToFetch = [\.date]
        let dates = ((try? context.fetch(habitFetch)) ?? []).map(\.date)

        let interval = Periods.month(containing: now)
        let start = interval.start
        let end = interval.end
        let monthRecords = (try? context.fetch(FetchDescriptor<Record>(predicate: #Predicate<Record> {
            $0.date >= start && $0.date < end && $0.ledgerID == ledgerID
        }))) ?? []
        let budgets = (try? context.fetch(FetchDescriptor<Budget>(predicate: #Predicate<Budget> { $0.ledgerID == ledgerID }))) ?? []

        let todayRecords = monthRecords.filter { calendar.isDate($0.date, inSameDayAs: now) }
        let monthBudget = budgets.first { $0.category == nil }?.amountCents ?? 0
        return make(PetFacts(
            speciesRaw: settings.petSpeciesRaw,
            customName: settings.petName,
            dates: dates,
            todayExpense: Stats.summary(todayRecords).expense,
            monthExpense: Stats.summary(monthRecords).expense,
            monthBudget: monthBudget,
            remainingDays: Periods.remainingDays(in: interval),
            currency: settings.baseCurrency,
            budgetPressured: budgetIsPressured(budgets: budgets, records: monthRecords, interval: interval, now: now),
            enabled: settings.petEnabled,
            customPetID: settings.petCustomID.isEmpty ? nil : settings.petCustomID,
            now: now,
            calendar: calendar
        ))
    }

    /// Matches the in-app budget warning: 80% used, already over, or the current pace runs out before month end.
    static func budgetIsPressured(budgets: [Budget], records: [Record], interval: DateInterval, now: Date) -> Bool {
        let expenses = Stats.counted(records).filter { $0.kind == .expense && interval.contains($0.date) }
        let elapsed = Double(Periods.elapsedDays(in: interval))
        for budget in budgets where budget.amountCents > 0 {
            let pool = budget.category.map { category in expenses.filter { $0.category?.uuid == category.uuid } } ?? expenses
            let spent = pool.reduce(0) { $0 + $1.baseAmountCents }
            let limit = budget.amountCents
            if spent >= limit { return true }
            if Double(spent) / Double(limit) >= 0.8 { return true }
            let daily = Double(spent) / max(elapsed, 1)
            if spent < limit, daily > 0, interval.contains(now) {
                let days = Double(limit - spent) / daily
                if now.addingTimeInterval(days * 86_400) < interval.end { return true }
            }
        }
        return false
    }
}

enum PetSnapshotCoding {
    static func data(for snapshot: PetSnapshot) throws -> Data {
        try JSONEncoder().encode(snapshot)
    }

    static func snapshot(from data: Data) -> PetSnapshot? {
        try? JSONDecoder().decode(PetSnapshot.self, from: data)
    }
}

enum PetStateStore {
    static let key = "petSnapshot.v1"

    /// An empty capture must not wipe a pet the app already published. That happens when the
    /// widget process cannot open the store and falls back to an empty in-memory container.
    static func choose(captured: PetSnapshot, stored: PetSnapshot?) -> PetSnapshot {
        if captured.recordedDays == 0, let stored, stored.recordedDays > 0 { return stored }
        return captured
    }

    static func load() -> PetSnapshot? {
        guard let data = AppGroup.defaults.data(forKey: key) else { return nil }
        return PetSnapshotCoding.snapshot(from: data)
    }

    /// Writes the snapshot into the App Group. Reloads widget timelines when the pet actually changed.
    static func save(_ snapshot: PetSnapshot, reloadWidgets: Bool = true) {
        if let existing = load(), existing.matches(snapshot) { return }
        var stored = snapshot
        stored.updatedAt = .now
        guard let data = try? PetSnapshotCoding.data(for: stored) else { return }
        AppGroup.defaults.set(data, forKey: key)
        if reloadWidgets { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Widget timeline entry point: trust a fresh capture, and keep the published snapshot if the capture is an empty stand-in.
    static func resolve(_ captured: PetSnapshot) -> PetSnapshot {
        let chosen = choose(captured: captured, stored: load())
        if chosen.matches(captured) { save(captured, reloadWidgets: false) }
        return chosen
    }
}
