import Foundation
import LocalAuthentication
import Observation
import SwiftData
import SwiftUI
import UIKit

// MARK: - Recurring

enum RecurringEngine {
    /// Creates records for every rule occurrence that is due. Safe to call repeatedly.
    @MainActor
    @discardableResult
    static func run(in context: ModelContext, now: Date = .now) -> Int {
        let rules = (try? context.fetch(FetchDescriptor<RecurringRule>(predicate: #Predicate<RecurringRule> { $0.isActive }))) ?? []
        let cal = Calendar.current
        var created = 0

        for rule in rules {
            var guardCount = 0
            while rule.nextDate <= now && guardCount < 400 {
                guardCount += 1
                if let end = rule.endDate, rule.nextDate > end {
                    rule.isActive = false
                    break
                }
                let record = Record(
                    kind: rule.kind,
                    amountCents: rule.amountCents,
                    date: rule.nextDate,
                    note: rule.note.isEmpty ? rule.name : rule.note,
                    category: DataStore.category(rule.categoryID, in: context),
                    account: DataStore.account(rule.accountID, in: context),
                    ledgerID: rule.ledgerID
                )
                if rule.kind == .transfer {
                    record.toAccount = DataStore.account(rule.toAccountID, in: context)
                }
                record.isRecurringInstance = true
                context.insert(record)
                rule.generatedCount += 1
                created += 1
                rule.nextDate = cal.date(byAdding: rule.frequency.component, value: max(1, rule.interval), to: rule.nextDate)
                    ?? now.addingTimeInterval(86_400)
            }
        }
        if created > 0 { try? context.save() }
        return created
    }

    static func upcoming(_ rule: RecurringRule, count: Int) -> [Date] {
        var dates: [Date] = []
        var date = rule.nextDate
        for _ in 0..<count {
            if let end = rule.endDate, date > end { break }
            dates.append(date)
            guard let next = Calendar.current.date(byAdding: rule.frequency.component, value: max(1, rule.interval), to: date) else { break }
            date = next
        }
        return dates
    }
}

// MARK: - Router

struct EntryRequest: Identifiable {
    let id = UUID()
    var record: Record?
    var kind: RecordKind = .expense
    var date: Date?
    var account: Account?
}

enum AppTab: Hashable {
    case home, stats, assets, me, search
}

@Observable
final class Router {
    static let shared = Router()
    var tab: AppTab = .home
    var entry: EntryRequest?
    var showAIEntry = false
    /// A Home screen to push next (consumed by HomeView).
    var homeRoute: HomeRoute?
    /// In-app budget alert banner.
    var banner: BudgetBanner?

    func showBanner(_ banner: BudgetBanner) {
        withAnimation(.bouncy) { self.banner = banner }
        let id = banner.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if self.banner?.id == id {
                withAnimation(.smooth) { self.banner = nil }
            }
        }
    }
    /// Record opened from Spotlight.
    var detail: Record?

    func handle(_ action: PendingAction) {
        switch action {
        case .newRecord: newRecord()
        case .aiEntry: showAIEntry = true
        }
    }

    /// moonmoney://add?kind=income, moonmoney://ai, moonmoney://stats
    func handle(url: URL) {
        guard url.scheme == "moonmoney" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch url.host {
        case "add":
            let kind: RecordKind = switch items.first(where: { $0.name == "kind" })?.value {
            case "income": .income
            case "transfer": .transfer
            default: .expense
            }
            newRecord(kind: kind)
        case "ai": showAIEntry = true
        case "stats": tab = .stats
        case "map":
            tab = .home
            homeRoute = .map
        case "alerts":
            tab = .home
            homeRoute = .alerts
        case "assets": tab = .assets
        default: tab = .home
        }
    }

    func newRecord(kind: RecordKind = .expense, date: Date? = nil, account: Account? = nil) {
        entry = EntryRequest(record: nil, kind: kind, date: date, account: account)
    }

    func edit(_ record: Record) {
        entry = EntryRequest(record: record, kind: record.kind)
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap() {
        guard AppSettings.shared.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        guard AppSettings.shared.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard AppSettings.shared.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - App lock

@Observable
final class AppLock {
    var isLocked: Bool
    var isAuthenticating = false

    init() {
        isLocked = AppSettings.shared.lockEnabled
    }

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "面容 ID"
        case .touchID: return "触控 ID"
        case .opticID: return "Optic ID"
        default: return "设备密码"
        }
    }

    var biometrySymbol: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.fill"
        }
    }

    func lockIfNeeded() {
        if AppSettings.shared.lockEnabled { isLocked = true }
    }

    @MainActor
    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解锁 MoonMoney 查看账目")
            if ok {
                withAnimation(.smooth) { isLocked = false }
            }
        } catch {
            // Stay locked; the user can retry from the lock screen.
        }
    }

    /// Used when turning the lock on, to confirm the user can authenticate.
    @MainActor
    static func verify() async -> Bool {
        let context = LAContext()
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "开启应用锁")) ?? false
    }
}
