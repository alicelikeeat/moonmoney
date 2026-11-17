import Observation
import SwiftData
import SwiftUI

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

    var nextStage: PetStage? { stage.next }

    /// Progress to the next stage, 0...1.
    var progress: Double { PetSnapshotLogic.progress(xp: xp, stage: stage) }

    init() {}

    init(snapshot: PetSnapshot) {
        species = snapshot.species
        name = snapshot.name
        stage = snapshot.stage
        mood = snapshot.mood
        xp = snapshot.xp
        streak = snapshot.streak
        recordedDays = snapshot.recordedDays
        todayCount = snapshot.todayCount
    }
}

// MARK: - Engine

@MainActor
enum PetEngine {
    /// Derives the pet from your bookkeeping: XP from days recorded, mood from habits and budget.
    static func compute(context: ModelContext) -> PetStatus {
        status(from: PetSnapshotLogic.capture(context: context), context: context)
    }

    static func status(from snapshot: PetSnapshot, context: ModelContext) -> PetStatus {
        var status = PetStatus(snapshot: snapshot)
        status.budgetHint = budgetHint(context: context)
        return status
    }

    private static func budgetHint(context: ModelContext) -> String? {
        let worst = BudgetMonitor.currentStatuses(context: context).max { $0.level < $1.level }
        guard let worst, worst.level >= .warning else { return nil }
        return [worst.headline, worst.forecast].compactMap { $0 }.joined(separator: "，")
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
        let snapshot = PetSnapshotLogic.capture(context: context)
        status = PetEngine.status(from: snapshot, context: context)
        PetStateStore.save(snapshot)
        Task { await PetActivityController.update(snapshot: snapshot) }
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
