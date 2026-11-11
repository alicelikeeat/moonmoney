import CoreSpotlight
import Foundation
import SwiftData
import UIKit
import UniformTypeIdentifiers
import UserNotifications
import WidgetKit

/// Hooks that run after launch and after records change.
@MainActor
enum AppServices {
    static func afterLaunch(context: ModelContext) {
        Task {
            await Notifications.reschedule(context: context)
            Spotlight.reindexAll(context: context)
        }
    }

    /// Call after inserting or editing records.
    static func recordsChanged(_ records: [Record], context: ModelContext) {
        WidgetCenter.shared.reloadAllTimelines()
        for record in records {
            Spotlight.index(record)
            if record.kind != .transfer, let category = record.category, !record.note.isEmpty {
                CategoryMemory.learn(record.note, categoryID: category.uuid)
            }
        }
        Task { await Notifications.checkBudget(context: context) }
    }

    static func recordDeleted(_ id: UUID) {
        WidgetCenter.shared.reloadAllTimelines()
        Spotlight.remove(id)
    }
}

// MARK: - Spotlight

enum Spotlight {
    static let domain = "com.moonmoney.records"

    static func item(for record: Record) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        let amount = Money.format(record.amountCents, code: record.currencyCode)
        attributes.title = "\(record.displayTitle) \(record.kind == .expense ? "-" : "+")\(amount)"
        var parts = [record.date.zh("yMMMd HH:mm")]
        if let account = record.account?.name { parts.append(account) }
        if !record.note.isEmpty { parts.append(record.note) }
        attributes.contentDescription = parts.joined(separator: " · ")
        attributes.keywords = [record.note, record.category?.name ?? "", record.account?.name ?? "", "记账", "MoonMoney"]
            + record.sortedTags.map(\.name)
        let item = CSSearchableItem(uniqueIdentifier: record.uuid.uuidString, domainIdentifier: domain, attributeSet: attributes)
        item.expirationDate = .distantFuture
        return item
    }

    static func index(_ record: Record) {
        CSSearchableIndex.default().indexSearchableItems([item(for: record)])
    }

    static func remove(_ id: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id.uuidString])
    }

    static func reindexAll(context: ModelContext) {
        var descriptor = FetchDescriptor<Record>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 2_000
        guard let records = try? context.fetch(descriptor) else { return }
        let items = records.map(item(for:))
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            CSSearchableIndex.default().indexSearchableItems(items)
        }
    }

    static func record(for identifier: String, in context: ModelContext) -> Record? {
        guard let id = UUID(uuidString: identifier) else { return nil }
        var descriptor = FetchDescriptor<Record>(predicate: #Predicate<Record> { $0.uuid == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

// MARK: - Notifications

@MainActor
enum Notifications {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Rebuilds the daily reminder and credit-card due reminders.
    static func reschedule(context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let settings = AppSettings.shared
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix("daily") || $0.hasPrefix("credit-") }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        if settings.dailyReminderEnabled {
            let content = UNMutableNotificationContent()
            content.title = "今天记账了吗？🌙"
            content.body = "花 10 秒记下今天的收支，月底不再一头雾水。"
            content.sound = .default
            var components = DateComponents()
            components.hour = settings.dailyReminderMinutes / 60
            components.minute = settings.dailyReminderMinutes % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: "daily", content: content, trigger: trigger))
        }

        if settings.creditDueAlertsEnabled {
            let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.typeRaw == 2 && !$0.isArchived })
            let cards = (try? context.fetch(descriptor)) ?? []
            for card in cards where card.dueDay > 0 {
                let content = UNMutableNotificationContent()
                content.title = "\(card.name) 即将还款"
                content.body = "还款日是每月 \(card.dueDay) 日，当前欠款 \(Money.format(max(0, -card.balanceCents), code: card.currencyCode))。"
                content.sound = .default
                var components = DateComponents()
                components.day = max(1, card.dueDay - 2)
                components.hour = 9
                components.minute = 30
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                try? await center.add(UNNotificationRequest(identifier: "credit-\(card.uuid.uuidString)", content: content, trigger: trigger))
            }
        }
    }

    /// Fires once per month per threshold (80% and 100%) of the overall budget.
    static func checkBudget(context: ModelContext) async {
        let settings = AppSettings.shared
        guard settings.budgetAlertsEnabled else { return }
        let ledgerID = settings.currentLedgerID
        let budgets = (try? context.fetch(FetchDescriptor<Budget>(predicate: #Predicate<Budget> { $0.ledgerID == ledgerID }))) ?? []
        guard let total = budgets.first(where: { $0.category == nil }), total.amountCents > 0 else { return }

        let interval = Periods.month(containing: .now)
        let start = interval.start, end = interval.end
        let records = (try? context.fetch(FetchDescriptor<Record>(predicate: #Predicate<Record> {
            $0.date >= start && $0.date < end && $0.ledgerID == ledgerID && $0.kindRaw == 0
        }))) ?? []
        let spent = Stats.summary(records).expense
        let ratio = Double(spent) / Double(total.amountCents)
        let monthKey = interval.start.zh("yyyyMM")

        for threshold in [100, 80] where ratio * 100 >= Double(threshold) {
            let key = "budgetAlert-\(monthKey)-\(threshold)"
            guard !AppGroup.defaults.bool(forKey: key) else { return }
            AppGroup.defaults.set(true, forKey: key)
            let content = UNMutableNotificationContent()
            content.title = threshold >= 100 ? "本月预算已超支" : "预算已用 80%"
            content.body = "已支出 \(Money.format(spent)) / 预算 \(Money.format(total.amountCents))，剩余 \(Periods.remainingDays(in: interval)) 天。"
            content.sound = .default
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: key, content: content, trigger: nil)
            )
            return
        }
    }
}

/// Shows notifications while the app is open, too.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
