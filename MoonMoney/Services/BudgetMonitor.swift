import Foundation
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// Live status of one budget for the current financial month.
struct BudgetStatus: Identifiable {
    enum Level: Int, Comparable {
        case ok, watch, warning, over
        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        var tint: Color {
            switch self {
            case .ok: .income
            case .watch: .yellow
            case .warning: .orange
            case .over: .expense
            }
        }

        var symbol: String {
            switch self {
            case .ok: "checkmark.seal.fill"
            case .watch: "eye.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .over: "flame.fill"
            }
        }
    }

    let id: UUID
    let budget: Budget
    let name: String
    let symbol: String
    let color: Color
    let image: Data?
    let limit: Int
    let spent: Int
    let projected: Int
    /// When the current pace runs the budget out before month end.
    let exhaustDate: Date?
    let level: Level
    /// Highest configured threshold already reached (0 = none).
    let reachedThreshold: Int

    var ratio: Double { Double(spent) / Double(max(limit, 1)) }
    var remaining: Int { limit - spent }
    var isTotal: Bool { budget.category == nil }

    var headline: String {
        if spent >= limit { return "\(name)已超支 \(Money.format(spent - limit))" }
        return "\(name)已用 \(InsightEngine.percent(ratio))"
    }

    var forecast: String? {
        if spent >= limit { return nil }
        if let exhaustDate { return "按当前速度，\(exhaustDate.zh("MMMd")) 就会用完" }
        if projected > limit { return "预计月底超支 \(Money.format(projected - limit))" }
        return nil
    }
}

@MainActor
enum BudgetMonitor {
    /// Pure computation from budgets and this month's records.
    static func statuses(budgets: [Budget], records: [Record], interval: DateInterval) -> [BudgetStatus] {
        let thresholds = AppSettings.shared.budgetThresholds.sorted()
        let expenses = Stats.counted(records).filter { $0.kind == .expense && interval.contains($0.date) }
        let elapsed = Double(Periods.elapsedDays(in: interval))
        let total = Double(Periods.totalDays(in: interval))
        let now = Date.now

        return budgets.filter { $0.amountCents > 0 }.map { budget in
            let pool = budget.category.map { category in expenses.filter { $0.category?.uuid == category.uuid } } ?? expenses
            let spent = pool.reduce(0) { $0 + $1.baseAmountCents }
            let daily = Double(spent) / max(elapsed, 1)
            let projected = Int(daily * total)
            var exhaust: Date?
            if spent < budget.amountCents, daily > 0, interval.contains(now) {
                let days = Double(budget.amountCents - spent) / daily
                let date = now.addingTimeInterval(days * 86_400)
                if date < interval.end { exhaust = date }
            }
            let percent = Double(spent) / Double(max(budget.amountCents, 1)) * 100
            let reached = thresholds.last { percent >= Double($0) } ?? 0
            let level: BudgetStatus.Level
            if percent >= 100 { level = .over }
            else if percent >= 80 || exhaust != nil { level = .warning }
            else if reached > 0 { level = .watch }
            else { level = .ok }

            return BudgetStatus(
                id: budget.uuid, budget: budget,
                name: budget.category?.name ?? "总预算",
                symbol: budget.category?.symbol ?? "target",
                color: budget.category?.color ?? .accentColor,
                image: budget.category?.iconImage,
                limit: budget.amountCents, spent: spent, projected: projected,
                exhaustDate: exhaust, level: level, reachedThreshold: reached
            )
        }
        .sorted { ($0.isTotal ? 1 : 0, $0.ratio) > ($1.isTotal ? 1 : 0, $1.ratio) }
    }

    static func currentStatuses(context: ModelContext) -> [BudgetStatus] {
        let ledgerID = AppSettings.shared.currentLedgerID
        let interval = Periods.month(containing: .now)
        let start = interval.start, end = interval.end
        let budgets = (try? context.fetch(FetchDescriptor<Budget>(predicate: #Predicate<Budget> { $0.ledgerID == ledgerID }))) ?? []
        let records = (try? context.fetch(FetchDescriptor<Record>(predicate: #Predicate<Record> {
            $0.date >= start && $0.date < end && $0.ledgerID == ledgerID && $0.kindRaw == 0
        }))) ?? []
        return statuses(budgets: budgets, records: records, interval: interval)
    }

    /// Fires each threshold once per month per budget, plus a weekly pace warning.
    /// Shows an in-app banner while the app is open, a notification otherwise.
    static func evaluate(context: ModelContext) async {
        let settings = AppSettings.shared
        guard settings.budgetAlertsEnabled else { return }
        let monthKey = Periods.month(containing: .now).start.zh("yyyyMM")
        let week = Calendar.current.component(.weekOfYear, from: .now)
        let defaults = AppGroup.defaults

        for status in currentStatuses(context: context) where status.budget.alertsEnabled {
            if status.reachedThreshold > 0 {
                let key = "budgetAlert-\(monthKey)-\(status.id.uuidString)-\(status.reachedThreshold)"
                if !defaults.bool(forKey: key) {
                    // Mark this and every lower threshold so they don't fire later.
                    for t in settings.budgetThresholds where t <= status.reachedThreshold {
                        defaults.set(true, forKey: "budgetAlert-\(monthKey)-\(status.id.uuidString)-\(t)")
                    }
                    let body = status.spent >= status.limit
                        ? "已支出 \(Money.format(status.spent)) / 预算 \(Money.format(status.limit))，请控制一下开销。"
                        : "已支出 \(Money.format(status.spent)) / \(Money.format(status.limit))，剩余 \(Money.format(status.remaining))。"
                    await deliver(id: key, title: status.headline, body: body, level: status.level)
                    continue
                }
            }
            if settings.budgetPaceAlerts, let forecast = status.forecast, status.spent < status.limit {
                let key = "budgetPace-\(monthKey)-\(week)-\(status.id.uuidString)"
                if !defaults.bool(forKey: key) && status.ratio >= 0.3 {
                    defaults.set(true, forKey: key)
                    await deliver(id: key, title: "\(status.name)花得有点快", body: forecast, level: .warning)
                }
            }
        }
    }

    private static func deliver(id: String, title: String, body: String, level: BudgetStatus.Level) async {
        if UIApplication.shared.applicationState == .active {
            Router.shared.showBanner(BudgetBanner(title: title, message: body, level: level))
            Haptics.warning()
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = level == .over ? .timeSensitive : .active
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

struct BudgetBanner: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let level: BudgetStatus.Level
}
