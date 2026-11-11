import AppIntents
import Foundation
import SwiftData
import SwiftUI

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

    /// Builds a container. The app uses CloudKit when entitled; the widget never syncs.
    static func makeContainer(cloudSync: Bool) -> ModelContainer {
        let schema = Schema(AppSchema.models)
        if cloudSync {
            let cloud = ModelConfiguration("MoonMoney", schema: schema, url: storeURL, cloudKitDatabase: .automatic)
            if let container = try? ModelContainer(for: schema, configurations: cloud) {
                return container
            }
        }
        let local = ModelConfiguration("MoonMoney", schema: schema, url: storeURL, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: local) {
            return container
        }
        // Last resort keeps the app usable even if the store is unreadable.
        let memory = ModelConfiguration("MoonMoney", schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: memory)
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
