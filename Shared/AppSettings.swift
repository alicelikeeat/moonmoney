import Foundation
import Observation

/// User preferences, persisted in UserDefaults.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults = AppGroup.defaults

    var currentLedgerID: UUID? {
        didSet { defaults.set(currentLedgerID?.uuidString, forKey: Keys.ledger) }
    }

    var defaultAccountID: UUID? {
        didSet { defaults.set(defaultAccountID?.uuidString, forKey: Keys.defaultAccount) }
    }

    var baseCurrency: String {
        didSet { defaults.set(baseCurrency, forKey: Keys.baseCurrency) }
    }

    /// Units of base currency per 1 unit of the keyed currency.
    var rates: [String: Double] {
        didSet {
            if let data = try? JSONEncoder().encode(rates) {
                defaults.set(data, forKey: Keys.rates)
            }
        }
    }

    /// The day a "month" starts on (1...28), e.g. payday.
    var monthStartDay: Int {
        didSet { defaults.set(monthStartDay, forKey: Keys.monthStart) }
    }

    var weekStartsOnMonday: Bool {
        didSet { defaults.set(weekStartsOnMonday, forKey: Keys.weekMonday) }
    }

    var lockEnabled: Bool {
        didSet { defaults.set(lockEnabled, forKey: Keys.lock) }
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) }
    }

    /// Keep the entry sheet open after saving so several records can be added in a row.
    var continuousEntry: Bool {
        didSet { defaults.set(continuousEntry, forKey: Keys.continuous) }
    }

    var hasSeeded: Bool {
        didSet { defaults.set(hasSeeded, forKey: Keys.seeded) }
    }

    /// Family members records can be attributed to ("我", "伴侣"…). Empty = feature hidden.
    var members: [String] {
        didSet { defaults.set(members, forKey: Keys.members) }
    }

    var dailyReminderEnabled: Bool {
        didSet { defaults.set(dailyReminderEnabled, forKey: Keys.dailyReminder) }
    }

    /// Minutes after midnight for the daily reminder.
    var dailyReminderMinutes: Int {
        didSet { defaults.set(dailyReminderMinutes, forKey: Keys.dailyReminderTime) }
    }

    var budgetAlertsEnabled: Bool {
        didSet { defaults.set(budgetAlertsEnabled, forKey: Keys.budgetAlerts) }
    }

    var creditDueAlertsEnabled: Bool {
        didSet { defaults.set(creditDueAlertsEnabled, forKey: Keys.creditAlerts) }
    }

    /// Use Apple Intelligence when the device supports it.
    var aiEnabled: Bool {
        didSet { defaults.set(aiEnabled, forKey: Keys.ai) }
    }

    private init() {
        currentLedgerID = defaults.string(forKey: Keys.ledger).flatMap(UUID.init(uuidString:))
        defaultAccountID = defaults.string(forKey: Keys.defaultAccount).flatMap(UUID.init(uuidString:))
        baseCurrency = defaults.string(forKey: Keys.baseCurrency) ?? "CNY"
        if let data = defaults.data(forKey: Keys.rates),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            rates = decoded
        } else {
            rates = ["USD": 7.1, "HKD": 0.91, "JPY": 0.047, "EUR": 7.7, "GBP": 9.0]
        }
        let start = defaults.integer(forKey: Keys.monthStart)
        monthStartDay = (1...28).contains(start) ? start : 1
        weekStartsOnMonday = defaults.object(forKey: Keys.weekMonday) as? Bool ?? true
        lockEnabled = defaults.bool(forKey: Keys.lock)
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        continuousEntry = defaults.bool(forKey: Keys.continuous)
        hasSeeded = defaults.bool(forKey: Keys.seeded)
        members = defaults.stringArray(forKey: Keys.members) ?? []
        dailyReminderEnabled = defaults.bool(forKey: Keys.dailyReminder)
        let minutes = defaults.object(forKey: Keys.dailyReminderTime) as? Int
        dailyReminderMinutes = minutes ?? 21 * 60
        budgetAlertsEnabled = defaults.object(forKey: Keys.budgetAlerts) as? Bool ?? true
        creditDueAlertsEnabled = defaults.object(forKey: Keys.creditAlerts) as? Bool ?? true
        aiEnabled = defaults.object(forKey: Keys.ai) as? Bool ?? true
    }

    /// Converts an amount in `code` into base currency cents.
    func convertToBase(_ cents: Int, from code: String) -> Int {
        guard code != baseCurrency else { return cents }
        guard let rate = rates[code], rate > 0 else { return cents }
        return Int((Double(cents) * rate).rounded())
    }

    /// Converts base currency cents into `code`.
    func convertFromBase(_ cents: Int, to code: String) -> Int {
        guard code != baseCurrency else { return cents }
        guard let rate = rates[code], rate > 0 else { return cents }
        return Int((Double(cents) / rate).rounded())
    }

    var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = weekStartsOnMonday ? 2 : 1
        return cal
    }

    private enum Keys {
        static let ledger = "currentLedgerID"
        static let defaultAccount = "defaultAccountID"
        static let baseCurrency = "baseCurrency"
        static let rates = "exchangeRates"
        static let monthStart = "monthStartDay"
        static let weekMonday = "weekStartsOnMonday"
        static let lock = "lockEnabled"
        static let haptics = "hapticsEnabled"
        static let continuous = "continuousEntry"
        static let seeded = "hasSeededDefaults"
        static let members = "members"
        static let dailyReminder = "dailyReminderEnabled"
        static let dailyReminderTime = "dailyReminderMinutes"
        static let budgetAlerts = "budgetAlertsEnabled"
        static let creditAlerts = "creditDueAlertsEnabled"
        static let ai = "aiEnabled"
    }
}

enum Currencies {
    static let common: [String] = ["CNY", "USD", "HKD", "JPY", "EUR", "GBP", "TWD", "KRW", "SGD", "AUD", "CAD", "THB", "MOP", "CHF"]

    static func name(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }
}
