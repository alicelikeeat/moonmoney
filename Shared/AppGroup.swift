import AppIntents
import Foundation
import SwiftData
import SwiftUI
import WidgetKit

/// Everything the app and its widget extension share: the App Group,
/// shared UserDefaults, and the SwiftData store location.
enum AppGroup {
    static let defaultIdentifier = "group.com.moonmoney.shared"

    /// Sideloading tools (AltStore / SideStore) rewrite app group IDs and
    /// record the real ones under `ALTAppGroups` in Info.plist.
    static var identifier: String {
        if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String],
           let match = groups.first(where: { $0.hasPrefix(defaultIdentifier) }) ?? groups.first {
            return match
        }
        return defaultIdentifier
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static let defaults: UserDefaults = {
        if containerURL != nil, let suite = UserDefaults(suiteName: identifier) {
            return suite
        }
        return .standard
    }()

    /// Where the store lived before App Group support (v1.0).
    static var legacyStoreURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("MoonMoney.store")
    }

    /// Store file inside the App Group when available, else the app's own Application Support.
    static var storeURL: URL {
        let base: URL
        if let group = containerURL {
            base = group.appendingPathComponent("Library/Application Support", isDirectory: true)
        } else {
            base = URL.applicationSupportDirectory
        }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("MoonMoney.store")
    }

    enum StoreMode: String {
        case appGroup = "App Group（与小组件共享）"
        case local = "本机"
        case memory = "临时内存（数据不会保存）"
    }

    /// How the last `makeContainer` call ended up storing data.
    nonisolated(unsafe) private(set) static var storeMode: StoreMode = .local

    /// Builds a container. The app uses CloudKit when entitled; the widget never syncs.
    static func makeContainer(cloudSync: Bool) -> ModelContainer {
        let schema = Schema(AppSchema.models)
        let url = storeURL
        if cloudSync { migrateLegacyStore(to: url) }
        let persistentMode: StoreMode = containerURL != nil ? .appGroup : .local

        if cloudSync {
            let cloud = ModelConfiguration("MoonMoney", schema: schema, url: url, cloudKitDatabase: .automatic)
            if let container = try? ModelContainer(for: schema, configurations: cloud) {
                storeMode = persistentMode
                return container
            }
        }
        let local = ModelConfiguration("MoonMoney", schema: schema, url: url, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: local) {
            storeMode = persistentMode
            return container
        }
        // The store could not be opened (e.g. a failed migration). Keep a backup and start fresh
        // on disk rather than silently running from memory.
        if cloudSync {
            backUpStore(at: url)
            if let container = try? ModelContainer(for: schema, configurations: local) {
                storeMode = persistentMode
                return container
            }
        }
        storeMode = .memory
        let memory = ModelConfiguration("MoonMoney", schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: memory)
    }

    private static func storeFiles(_ url: URL) -> [URL] {
        [url, URL(fileURLWithPath: url.path + "-shm"), URL(fileURLWithPath: url.path + "-wal")]
    }

    /// Copies a v1.0 store into the App Group the first time the app runs with one.
    private static func migrateLegacyStore(to url: URL) {
        let fm = FileManager.default
        let legacy = legacyStoreURL
        guard legacy.standardizedFileURL != url.standardizedFileURL,
              fm.fileExists(atPath: legacy.path),
              !fm.fileExists(atPath: url.path) else { return }
        for (source, target) in zip(storeFiles(legacy), storeFiles(url)) where fm.fileExists(atPath: source.path) {
            try? fm.copyItem(at: source, to: target)
        }
    }

    private static func backUpStore(at url: URL) {
        let fm = FileManager.default
        let stamp = Int(Date.now.timeIntervalSince1970)
        for file in storeFiles(url) where fm.fileExists(atPath: file.path) {
            let backup = URL(fileURLWithPath: file.path.replacingOccurrences(of: "MoonMoney.store", with: "MoonMoney-backup-\(stamp).store"))
            try? fm.moveItem(at: file, to: backup)
        }
    }
}

// MARK: - Pending actions (widgets / controls → app)

enum PendingAction: String {
    case newRecord, aiEntry
}

enum PendingActions {
    private static let key = "pendingAction"

    static func set(_ action: PendingAction) {
        AppGroup.defaults.set(action.rawValue, forKey: key)
    }

    static func consume() -> PendingAction? {
        guard let raw = AppGroup.defaults.string(forKey: key) else { return nil }
        AppGroup.defaults.removeObject(forKey: key)
        return PendingAction(rawValue: raw)
    }
}

/// Opens the app straight into the entry sheet. Shared so Control Center can use it.
struct OpenEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "打开记账面板"
    static let description = IntentDescription("打开 MoonMoney 并直接进入记一笔。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingActions.set(.newRecord)
        NotificationCenter.default.post(name: .moonMoneyPendingAction, object: nil)
        return .result()
    }
}

/// Opens the AI one-sentence entry sheet.
struct OpenAIEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "打开 AI 记账"
    static let description = IntentDescription("打开 MoonMoney 的一句话智能记账。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingActions.set(.aiEntry)
        NotificationCenter.default.post(name: .moonMoneyPendingAction, object: nil)
        return .result()
    }
}

extension Notification.Name {
    static let moonMoneyPendingAction = Notification.Name("moonMoneyPendingAction")
}

// MARK: - Category memory

/// Learns which category the user picks for a given note / merchant,
/// so AI parsing, Siri and auto-bookkeeping get smarter over time.
enum CategoryMemory {
    private static let key = "categoryMemory"

    private static var table: [String: String] {
        get { AppGroup.defaults.dictionary(forKey: key) as? [String: String] ?? [:] }
        set { AppGroup.defaults.set(newValue, forKey: key) }
    }

    static func learn(_ text: String, categoryID: UUID) {
        let keyText = normalize(text)
        guard keyText.count >= 2, keyText.count <= 24 else { return }
        var current = table
        current[keyText] = categoryID.uuidString
        if current.count > 400 {
            current = Dictionary(uniqueKeysWithValues: current.prefix(300).map { ($0.key, $0.value) })
        }
        table = current
    }

    /// Longest learned phrase contained in `text` wins.
    static func lookup(_ text: String) -> UUID? {
        let haystack = normalize(text)
        guard !haystack.isEmpty else { return nil }
        let match = table
            .filter { haystack.contains($0.key) || $0.key.contains(haystack) }
            .max { $0.key.count < $1.key.count }
        return match.flatMap { UUID(uuidString: $0.value) }
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}

// MARK: - Symbol or emoji glyph

/// Renders an SF Symbol name, or the string itself when it is an emoji.
struct SymbolGlyph: View {
    let symbol: String

    init(_ symbol: String) { self.symbol = symbol }

    static func isEmoji(_ symbol: String) -> Bool {
        !symbol.isEmpty && !symbol.contains(where: \.isASCII)
    }

    var body: some View {
        if Self.isEmoji(symbol) {
            Text(symbol)
        } else {
            Image(systemName: symbol)
        }
    }
}

// MARK: - One-tap logging from widgets

/// Logs a frequent expense without opening the app (interactive widget button).
struct QuickLogIntent: AppIntent {
    static let title: LocalizedStringResource = "一键记账"
    static let description = IntentDescription("从小组件直接记录一笔常用支出。")
    static let isDiscoverable = false

    @Parameter(title: "金额（分）")
    var amountCents: Int

    @Parameter(title: "分类 ID")
    var categoryID: String

    @Parameter(title: "备注")
    var note: String

    init() {}

    init(amountCents: Int, categoryID: UUID, note: String) {
        self.amountCents = amountCents
        self.categoryID = categoryID.uuidString
        self.note = note
    }

    func perform() async throws -> some IntentResult {
        guard amountCents > 0 else { return .result() }
        let context = ModelContext(QuickLogStore.container)
        let settings = AppSettings.shared
        settings.reload()

        let categoryUUID = UUID(uuidString: categoryID) ?? UUID()
        var categoryFetch = FetchDescriptor<BillCategory>(predicate: #Predicate<BillCategory> { $0.uuid == categoryUUID })
        categoryFetch.fetchLimit = 1
        let category = try? context.fetch(categoryFetch).first

        let accountUUID = settings.defaultAccountID ?? UUID()
        var accountFetch = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.uuid == accountUUID })
        accountFetch.fetchLimit = 1
        var account = try? context.fetch(accountFetch).first
        if account == nil {
            var fallback = FetchDescriptor<Account>(predicate: #Predicate<Account> { !$0.isArchived }, sortBy: [SortDescriptor(\.order)])
            fallback.fetchLimit = 1
            account = try? context.fetch(fallback).first
        }

        let record = Record(kind: .expense, amountCents: amountCents, note: note,
                            category: category, account: account, ledgerID: settings.currentLedgerID)
        context.insert(record)
        try context.save()
        AppGroup.defaults.set(["title": (category?.name ?? "支出") + (note.isEmpty ? "" : " · \(note)"),
                               "cents": amountCents, "at": Date.now.timeIntervalSince1970],
                              forKey: QuickLogStore.lastLogKey)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

enum QuickLogStore {
    static let lastLogKey = "lastQuickLog"
    /// A local (non-syncing) container for writes coming from widgets.
    static let container = AppGroup.makeContainer(cloudSync: false)
}
