import SwiftData
import SwiftUI
import WidgetKit

struct PetEntry: TimelineEntry {
    let date: Date
    let snapshot: PetSnapshot
    var frameIndex: Int = 0
}

struct PetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PetEntry {
        PetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PetEntry) -> Void) {
        completion(PetEntry(date: .now, snapshot: context.isPreview ? .placeholder : load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PetEntry>) -> Void) {
        let snapshot = load()
        let frames = max(1, PetCustomLibrary.frameCount(id: snapshot.customPetID))
        let steps = min(frames, 4)
        let spacing: TimeInterval = frames > 1 ? 900 : 1_800
        let entries = (0..<steps).map { index in
            PetEntry(date: .now.addingTimeInterval(Double(index) * spacing), snapshot: snapshot, frameIndex: index)
        }
        let calendar = Calendar.current
        let next = entries.last?.date.addingTimeInterval(spacing) ?? .now.addingTimeInterval(spacing)
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? next
        completion(Timeline(entries: entries, policy: .after(min(next, midnight))))
    }

    private func load() -> PetSnapshot {
        let context = ModelContext(WidgetData.container)
        return PetStateStore.resolve(PetSnapshotLogic.capture(context: context))
    }
}

struct PetWidget: Widget {
    let kind = "MoonMoneyPet"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PetProvider()) { entry in
            PetWidgetView(snapshot: entry.snapshot, frameIndex: entry.frameIndex)
        }
        .configurationDisplayName("我的宠物")
        .description("宠物的样子和心情，加上今天花了多少。")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}
