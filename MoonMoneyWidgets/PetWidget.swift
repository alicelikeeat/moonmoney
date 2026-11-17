import SwiftData
import SwiftUI
import WidgetKit

struct PetEntry: TimelineEntry {
    let date: Date
    let snapshot: PetSnapshot
}

struct PetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PetEntry {
        PetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PetEntry) -> Void) {
        completion(PetEntry(date: .now, snapshot: context.isPreview ? .placeholder : load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PetEntry>) -> Void) {
        let entry = PetEntry(date: .now, snapshot: load())
        let calendar = Calendar.current
        let next = calendar.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1_800)
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? next
        completion(Timeline(entries: [entry], policy: .after(min(next, midnight))))
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
            PetWidgetView(entry: entry)
        }
        .configurationDisplayName("我的宠物")
        .description("宠物的样子和心情，加上今天花了多少。")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct PetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PetEntry

    private var pet: PetSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: Text(pet.enabled ? "\(pet.name) · \(pet.hint)" : "宠物已关闭 · \(pet.hint)")
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                sprite(52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pet.name).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    Text(pet.enabled ? "\(pet.stage.title) · \(pet.mood.title)" : "已在 App 里关闭")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(pet.hint)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if pet.monthBudget > 0 {
                PetBudgetBar(spent: pet.monthExpense, budget: pet.monthBudget)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Rectangle().fill(.background) }
        .widgetURL(PetLink.page)
    }

    private var medium: some View {
        HStack(spacing: 12) {
            sprite(84)
            VStack(alignment: .leading, spacing: 4) {
                Text(pet.name).font(.headline).lineLimit(1)
                Text(pet.enabled ? "\(pet.stage.title) · \(pet.mood.title)" : "已在 App 里关闭")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(pet.spendingLine)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(pet.hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if pet.monthBudget > 0 {
                    PetBudgetBar(spent: pet.monthExpense, budget: pet.monthBudget)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(for: .widget) { Rectangle().fill(.background) }
        .widgetURL(PetLink.page)
    }

    private var circular: some View {
        sprite(36)
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(PetLink.page)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            sprite(36)
            VStack(alignment: .leading, spacing: 1) {
                Text(pet.name).font(.headline).lineLimit(1).widgetAccentable()
                Text(pet.hint).font(.caption).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(PetLink.page)
    }

    private func sprite(_ side: CGFloat) -> some View {
        PetPixel(species: pet.species, stage: pet.stage, expression: pet.expression)
            .frame(width: side, height: side)
            .opacity(pet.enabled ? 1 : 0.45)
            .accessibilityLabel("\(pet.name)，\(pet.stage.title)，\(pet.mood.title)")
    }
}

struct PetPixel: View {
    var species: PetSpecies
    var stage: PetStage
    var expression: PetExpression

    var body: some View {
        PetSpriteView(species: species, stage: stage, expression: expression, centered: true)
            .widgetAccentedRenderingMode(.fullColor)
            .accessibilityHidden(true)
    }
}

struct PetBudgetBar: View {
    var spent: Int
    var budget: Int

    var body: some View {
        let ratio = budget > 0 ? min(1, Double(max(0, spent)) / Double(budget)) : 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.fill.tertiary)
                Capsule()
                    .fill(ratio >= 1 ? Color.expense : (ratio >= 0.8 ? Color.orange : Color.income))
                    .frame(width: max(4, geo.size.width * ratio))
            }
        }
        .frame(height: 6)
        .accessibilityLabel("本月预算已用 \(Int(ratio * 100))%")
    }
}
