import ActivityKit
import Foundation
import SwiftData

/// Start and stop the daily bookkeeping Live Activity from anywhere in the app.
@MainActor
enum PetSessionActions {
    /// Starts a session, or ends the one already on screen. Returns a short status sentence.
    static func toggle(context: ModelContext) async -> String {
        PetCenter.shared.refresh(context: context)
        let snapshot = PetStateStore.load() ?? PetSnapshotLogic.capture(context: context)
        let live = Activity<BookkeepingAttributes>.activities.contains { Date.now < $0.attributes.endsAt }
        if PetSessionStore.isActive(), live {
            await PetActivityController.stop(snapshot: snapshot)
            return "已结束今日记账"
        }
        if let error = await PetActivityController.start(snapshot: snapshot) {
            return error
        }
        return "已开始今日记账，\(snapshot.name)会出现在灵动岛和锁屏上。"
    }
}
