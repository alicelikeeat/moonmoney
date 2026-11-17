import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen banner and Dynamic Island for the daily bookkeeping session.
struct PetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BookkeepingAttributes.self) { context in
            PetSessionBanner(state: context.state, endsAt: context.attributes.endsAt, stale: context.isStale)
                .activityBackgroundTint(Color(hex: "#6C48E6").opacity(0.28))
                .widgetURL(PetLink.page)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PetPixel(species: context.state.species, stage: context.state.stage, expression: context.state.expression)
                        .frame(width: 56, height: 56)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("今日")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(Money.compact(context.state.todayExpense))
                            .font(.headline.monospacedDigit())
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.name).font(.headline).lineLimit(1)
                        Text(context.isStale ? "今日已结束" : context.state.mood.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    PetSessionDetails(state: context.state, endsAt: context.attributes.endsAt, stale: context.isStale)
                }
            } compactLeading: {
                PetPixel(species: context.state.species, stage: context.state.stage, expression: context.state.expression)
                    .frame(width: 26, height: 26)
            } compactTrailing: {
                Text(context.isStale ? "结束" : Money.compact(context.state.todayExpense))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .widgetAccentable()
            } minimal: {
                PetPixel(species: context.state.species, stage: context.state.stage, expression: context.state.expression)
                    .frame(width: 18, height: 18)
            }
            .widgetURL(PetLink.page)
            .keylineTint(Color(hex: "#FFB04A"))
        }
    }
}
