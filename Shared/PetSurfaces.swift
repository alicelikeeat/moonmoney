import SwiftUI
import WidgetKit

struct PetPixel: View {
    var species: PetSpecies
    var stage: PetStage
    var expression: PetExpression

    var body: some View {
        PetSpriteView(species: species, stage: stage, expression: expression, centered: true)
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

/// Home-screen and lock-screen pet widget. `family` overrides the widget environment so the app can preview it.
struct PetWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    var snapshot: PetSnapshot
    var family: WidgetFamily? = nil

    private var resolvedFamily: WidgetFamily { family ?? environmentFamily }
    private var pet: PetSnapshot { snapshot }

    var body: some View {
        switch resolvedFamily {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

/// Lock-screen Live Activity banner. The Dynamic Island uses the same sprite and copy.
struct PetSessionBanner: View {
    let state: BookkeepingAttributes.ContentState
    let endsAt: Date
    let stale: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PetPixel(species: state.species, stage: state.stage, expression: state.expression)
                .frame(width: 64, height: 64)
                .accessibilityLabel("\(state.name)，\(state.mood.title)")
            PetSessionDetails(state: state, endsAt: endsAt, stale: stale)
        }
        .padding(14)
    }
}

struct PetSessionDetails: View {
    let state: BookkeepingAttributes.ContentState
    let endsAt: Date
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stale ? "今日记账已结束" : state.spendingLine)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if state.monthBudget > 0 {
                PetBudgetBar(spent: state.monthExpense, budget: state.monthBudget)
            }
            HStack(spacing: 8) {
                Text(state.hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if stale {
                    Text(state.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if Date.now < endsAt {
                    Text(timerInterval: Date.now...endsAt, countsDown: true)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: 78, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
