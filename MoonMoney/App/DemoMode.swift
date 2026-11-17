import Foundation
import SwiftData

/// Launch arguments used by CI to screenshot the app in the simulator:
///   -demoData          seed ~3 months of sample records and a budget (once)
///   -skin liquid|pixel  pick the interface skin
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
        if let index = arguments.firstIndex(of: "-skin"), index + 1 < arguments.count {
            AppSettings.shared.skinRaw = arguments[index + 1]
        }
        if let index = arguments.firstIndex(of: "-pixelFont"), index + 1 < arguments.count {
            AppSettings.shared.pixelFontRaw = arguments[index + 1]
        }
        if let index = arguments.firstIndex(of: "-moneyFont"), index + 1 < arguments.count {
            AppSettings.shared.moneyFontRaw = arguments[index + 1]
        }
        if arguments.contains("-customPet") {
            installDemoCustomPet()
        }
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
        case "skins":
            router.tab = .me
            router.showSkinPicker = true
        case "map", "places", "alerts", "calendar", "pet", "surfaces":
            router.tab = .home
            router.homeRoute = ["map": .map, "places": .places, "alerts": .alerts, "calendar": .calendar, "pet": .pet, "surfaces": .surfaces][screen]
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

    /// A solid pixel pet so the screenshot run can show a custom pet without a photo library.
    private static func installDemoCustomPet() {
        var pixels = [PetPixelColor](repeating: .clear, count: 32 * 32)
        for y in 6..<26 {
            for x in 8..<24 {
                let ear = y < 12 && (x < 12 || x > 19)
                pixels[y * 32 + x] = ear
                    ? PetPixelColor(r: 255, g: 150, b: 190, a: 255)
                    : PetPixelColor(r: 255, g: 196, b: 92, a: 255)
            }
        }
        let bitmap = PetBitmap(width: 32, height: 32, pixels: pixels)
        guard let raster = PetPixelate.rasters(from: [bitmap], paletteCount: 6, cropInset: 0).first else { return }
        let id = "demo-custom"
        PetCustomLibrary.save(PetCustomRecord(id: id, name: "小像素", frames: [raster], createdAt: .now))
        AppSettings.shared.petCustomID = id
        AppSettings.shared.petName = "小像素"
    }
}
