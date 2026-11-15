import Foundation
import Observation
import SwiftData
import SwiftUI

// MARK: - Sprite data types

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

enum PetSpecies: String, CaseIterable, Identifiable {
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

enum PetStage: Int, Comparable {
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

    var scale: CGFloat {
        switch self {
        case .egg, .adult: 1
        case .baby: 0.78
        case .teen: 0.9
        }
    }
}

enum PetMood {
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

enum PetExpression {
    case normal, blink, happy, eat, sleep
}

struct PetStatus {
    var species: PetSpecies = .rabbit
    var name = "小月兔"
    var stage: PetStage = .egg
    var mood: PetMood = .normal
    var xp = 0
    var streak = 0
    var recordedDays = 0
    var todayCount = 0
    var budgetHint: String?

    var nextStage: PetStage? {
        switch stage {
        case .egg: .baby
        case .baby: .teen
        case .teen: .adult
        case .adult: nil
        }
    }

    /// Progress to the next stage, 0...1.
    var progress: Double {
        guard let next = nextStage else { return 1 }
        let start = stage.threshold
        return Double(xp - start) / Double(max(1, next.threshold - start))
    }
}

// MARK: - Engine

@MainActor
enum PetEngine {
    /// Derives the pet from your bookkeeping: XP from days recorded, mood from habits and budget.
    static func compute(context: ModelContext) -> PetStatus {
        let settings = AppSettings.shared
        var status = PetStatus()
        status.species = PetSpecies(rawValue: settings.petSpeciesRaw) ?? .rabbit
        status.name = settings.petName.trimmingCharacters(in: .whitespaces).isEmpty ? status.species.defaultName : settings.petName

        var descriptor = FetchDescriptor<Record>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.propertiesToFetch = [\.date]
        let dates = ((try? context.fetch(descriptor)) ?? []).map(\.date).filter { $0 <= .now }
        let cal = Calendar.current
        let days = Set(dates.map { cal.startOfDay(for: $0) })
        let today = cal.startOfDay(for: .now)

        status.recordedDays = days.count
        status.todayCount = dates.filter { cal.isDate($0, inSameDayAs: today) }.count
        var cursor = days.contains(today) ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
        while days.contains(cursor) {
            status.streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        status.xp = days.count * 10 + min(dates.count, 2_000) * 2 + min(status.streak, 60) * 3

        if dates.isEmpty { status.stage = .egg }
        else if status.xp >= PetStage.adult.threshold { status.stage = .adult }
        else if status.xp >= PetStage.teen.threshold { status.stage = .teen }
        else { status.stage = .baby }

        let worst = BudgetMonitor.currentStatuses(context: context).max { $0.level < $1.level }
        if let worst, worst.level >= .warning {
            status.budgetHint = [worst.headline, worst.forecast].compactMap { $0 }.joined(separator: "，")
        }

        let lastDay = days.max()
        if let lastDay, let gap = cal.dateComponents([.day], from: lastDay, to: today).day, gap >= 2 {
            status.mood = .sleepy
        } else if let worst, worst.level >= .warning {
            status.mood = .worried
        } else if status.todayCount == 0 && status.stage != .egg {
            status.mood = .hungry
        } else if status.todayCount > 0 {
            status.mood = .happy
        } else {
            status.mood = .normal
        }
        return status
    }
}

// MARK: - Live state shared by every pet view

@MainActor
@Observable
final class PetCenter {
    static let shared = PetCenter()

    private(set) var status = PetStatus()
    private(set) var eatUntil = Date.distantPast
    private(set) var cheerUntil = Date.distantPast
    private(set) var hopUntil = Date.distantPast
    private(set) var speech: String?
    private var speechToken = UUID()
    private var tipIndex = 0

    func refresh(context: ModelContext) {
        status = PetEngine.compute(context: context)
    }

    /// Called after records are saved: the pet catches a coin and may level up.
    func fed(context: ModelContext) {
        let before = status.stage
        refresh(context: context)
        let now = Date.now
        eatUntil = now.addingTimeInterval(2.2)
        if status.stage > before {
            cheerUntil = now.addingTimeInterval(3.5)
            say(before == .egg ? "我出生啦！我是\(status.name)～" : "我长大了！现在是\(status.stage.title)\(status.name)！")
        } else {
            say(["好吃！", "谢谢投喂～", "又攒了一点经验！", "+1 记账，好习惯！"].randomElement() ?? "好吃！")
        }
    }

    /// Tapping the pet: a hop and a tip.
    func poke() {
        hopUntil = Date.now.addingTimeInterval(0.6)
        say(nextTip())
        Haptics.tap()
    }

    private func nextTip() -> String {
        var tips: [String] = []
        switch status.mood {
        case .sleepy: tips.append("Zzz…记一笔就能叫醒我")
        case .hungry: tips.append("今天还没记账，我有点饿…")
        case .worried: if let hint = status.budgetHint { tips.append(hint) }
        case .happy: tips.append("今天记了 \(status.todayCount) 笔，吃饱饱！")
        case .normal: break
        }
        if status.stage == .egg { tips.append("记下第一笔账，我就会破壳哦！") }
        if status.streak >= 2 { tips.append("已经连续记账 \(status.streak) 天啦！") }
        if let next = status.nextStage, status.stage != .egg {
            tips.append("再攒 \(max(0, next.threshold - status.xp)) 点经验就能长成\(next.title)！")
        }
        tips += status.species.catchphrases
        defer { tipIndex += 1 }
        return tips[tipIndex % tips.count]
    }

    private func say(_ text: String) {
        let token = UUID()
        speechToken = token
        withAnimation(.snappy) { speech = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            if speechToken == token { withAnimation(.smooth) { speech = nil } }
        }
    }
}
