import Foundation
import SwiftData

/// Launch arguments used by CI to screenshot the app in the simulator:
///   -demoData          seed ~3 months of sample records and a budget (once)
///   -screen <name>     home | stats | assets | me | search | entry | ai | calendar | reports
@MainActor
enum DemoMode {
    static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var screen: String? {
        guard let index = arguments.firstIndex(of: "-screen"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func applyIfRequested() {
        let context = DataStore.context
        if arguments.contains("-demoData") {
            let count = (try? context.fetchCount(FetchDescriptor<Record>())) ?? 0
            if count == 0 {
                Seed.insertSampleRecords(into: context)
                let ledgerID = AppSettings.shared.currentLedgerID
                context.insert(Budget(amountCents: 600_000, ledgerID: ledgerID))
                try? context.save()
            }
        }
        guard let screen else { return }
        let router = Router.shared
        switch screen {
        case "stats": router.tab = .stats
        case "map", "places", "alerts", "calendar":
            router.tab = .home
            router.homeRoute = ["map": .map, "places": .places, "alerts": .alerts, "calendar": .calendar][screen]
        case "assets": router.tab = .assets
        case "me": router.tab = .me
        case "search": router.tab = .search
        case "entry":
            router.tab = .home
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                router.newRecord()
            }
        case "ai":
            router.tab = .home
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                router.showAIEntry = true
            }
        default: router.tab = .home
        }
    }
}
