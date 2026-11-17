import ActivityKit
import Foundation

/// A daily bookkeeping session shown on the Lock Screen and in the Dynamic Island.
/// The session belongs to one calendar day and goes stale at the next midnight.
struct BookkeepingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var speciesRaw: String
        var name: String
        var stageRaw: Int
        var moodRaw: String
        var expressionRaw: String
        var todayExpense: Int
        var dailyBudget: Int
        var monthExpense: Int
        var monthBudget: Int
        var currency: String
        var streak: Int
        var hint: String

        var species: PetSpecies { PetSpecies(rawValue: speciesRaw) ?? .rabbit }
        var stage: PetStage { PetStage(rawValue: stageRaw) ?? .egg }
        var mood: PetMood { PetMood(rawValue: moodRaw) ?? .normal }
        var expression: PetExpression { PetExpression(rawValue: expressionRaw) ?? .normal }

        var spendingLine: String {
            PetCopy.spendingLine(todayExpense: todayExpense, monthBudget: monthBudget, dailyBudget: dailyBudget, currency: currency)
        }

        init(_ snapshot: PetSnapshot) {
            speciesRaw = snapshot.speciesRaw
            name = snapshot.name
            stageRaw = snapshot.stageRaw
            moodRaw = snapshot.moodRaw
            expressionRaw = snapshot.expressionRaw
            todayExpense = snapshot.todayExpense
            dailyBudget = snapshot.dailyBudget
            monthExpense = snapshot.monthExpense
            monthBudget = snapshot.monthBudget
            currency = snapshot.currency
            streak = snapshot.streak
            hint = snapshot.hint
        }
    }

    var dayStart: Date
    var endsAt: Date
}

enum PetSessionStore {
    private static let untilKey = "petSessionEndsAt"

    static var endsAt: Date? {
        let raw = AppGroup.defaults.double(forKey: untilKey)
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    static func isActive(now: Date = .now) -> Bool {
        PetSnapshotLogic.sessionIsActive(endsAt: endsAt, now: now)
    }

    @discardableResult
    static func begin(now: Date = .now, calendar: Calendar = .current) -> Date {
        let end = PetSnapshotLogic.endOfDay(for: now, calendar: calendar)
        AppGroup.defaults.set(end.timeIntervalSince1970, forKey: untilKey)
        return end
    }

    static func restore(endsAt: Date) {
        AppGroup.defaults.set(endsAt.timeIntervalSince1970, forKey: untilKey)
    }

    static func clear() {
        AppGroup.defaults.removeObject(forKey: untilKey)
    }
}

/// Starts, updates, and ends the daily session. Local updates only — no push token —
/// so a free Apple ID can run it when the widget extension is installed.
@MainActor
enum PetActivityController {
    static func content(for snapshot: PetSnapshot, endsAt: Date) -> ActivityContent<BookkeepingAttributes.ContentState> {
        let score = (snapshot.mood == .worried || snapshot.dailyBudget < 0) ? 100.0 : 50.0
        return ActivityContent(state: BookkeepingAttributes.ContentState(snapshot), staleDate: endsAt, relevanceScore: score)
    }

    /// Nil when the session is on screen. Otherwise a sentence the UI can show.
    static func start(snapshot: PetSnapshot, now: Date = .now) async -> String? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "系统没有打开实时活动。请到「设置 → MoonMoney → 实时活动」允许后，再开始今日记账。"
        }
        let endsAt = PetSessionStore.begin(now: now)
        let attributes = BookkeepingAttributes(dayStart: Calendar.current.startOfDay(for: now), endsAt: endsAt)
        for activity in Activity<BookkeepingAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        do {
            _ = try Activity.request(attributes: attributes, content: content(for: snapshot, endsAt: endsAt), pushType: nil)
            return nil
        } catch {
            PetSessionStore.clear()
            return "没能开始今日记账。精简版安装不含小组件，灵动岛和锁屏横幅也不会出现；请安装完整版后再试。"
        }
    }

    static func update(snapshot: PetSnapshot, now: Date = .now) async {
        await endIfExpired(now: now)
        guard PetSessionStore.isActive(now: now), let endsAt = PetSessionStore.endsAt else { return }
        let content = content(for: snapshot, endsAt: endsAt)
        for activity in Activity<BookkeepingAttributes>.activities where now < activity.attributes.endsAt {
            await activity.update(content)
        }
    }

    static func stop(snapshot: PetSnapshot? = nil) async {
        let content = snapshot.flatMap { snap -> ActivityContent<BookkeepingAttributes.ContentState>? in
            guard let endsAt = PetSessionStore.endsAt else { return nil }
            return ActivityContent(state: BookkeepingAttributes.ContentState(snap), staleDate: endsAt)
        }
        for activity in Activity<BookkeepingAttributes>.activities {
            await activity.end(content, dismissalPolicy: .immediate)
        }
        PetSessionStore.clear()
    }

    /// Ends sessions whose day has passed. The banner also goes stale at midnight on its own;
    /// this removes it the next time the app or a widget is running.
    static func endIfExpired(now: Date = .now) async {
        for activity in Activity<BookkeepingAttributes>.activities where now >= activity.attributes.endsAt {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        if let ends = PetSessionStore.endsAt, now >= ends {
            PetSessionStore.clear()
        }
    }

    /// Aligns the stored flag with the activities the system is actually showing.
    static func reconcile(now: Date = .now) async {
        await endIfExpired(now: now)
        let live = Activity<BookkeepingAttributes>.activities.filter { now < $0.attributes.endsAt }
        if let ends = live.first?.attributes.endsAt {
            PetSessionStore.restore(endsAt: ends)
        } else {
            PetSessionStore.clear()
        }
    }
}
