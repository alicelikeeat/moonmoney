import Charts
import SwiftData
import SwiftUI
import WidgetKit

// MARK: - Entry

struct WidgetCategory: Hashable {
    let name: String
    let symbol: String
    let colorHex: String
    let cents: Int
}

struct WidgetDay: Hashable, Identifiable {
    var id: Date { date }
    let date: Date
    let cents: Int
}

struct WidgetRecent: Hashable, Identifiable {
    let id: UUID
    let title: String
    let symbol: String
    let colorHex: String
    let cents: Int
    let isIncome: Bool
    let date: Date
}

struct SummaryEntry: TimelineEntry {
    let date: Date
    let currency: String
    let monthTitle: String
    let monthExpense: Int
    let monthIncome: Int
    let todayExpense: Int
    let budget: Int
    let top: [WidgetCategory]
    let week: [WidgetDay]
    let recent: [WidgetRecent]

    var budgetRatio: Double { budget > 0 ? Double(monthExpense) / Double(budget) : 0 }
    var budgetRemaining: Int { budget - monthExpense }

    static var placeholder: SummaryEntry {
        let cal = Calendar.current
        return SummaryEntry(
            date: .now, currency: "CNY", monthTitle: "11月",
            monthExpense: 386_240, monthIncome: 1_850_000, todayExpense: 6_850, budget: 600_000,
            top: [
                WidgetCategory(name: "餐饮", symbol: "fork.knife", colorHex: "#FF9F0A", cents: 128_000),
                WidgetCategory(name: "交通", symbol: "tram.fill", colorHex: "#0A84FF", cents: 56_000),
                WidgetCategory(name: "购物", symbol: "bag.fill", colorHex: "#FF375F", cents: 49_900),
            ],
            week: (0..<7).reversed().map { offset in
                WidgetDay(date: cal.date(byAdding: .day, value: -offset, to: .now) ?? .now, cents: [8_000, 12_500, 4_200, 21_000, 6_600, 15_000, 6_850][offset])
            },
            recent: [
                WidgetRecent(id: UUID(), title: "餐饮", symbol: "fork.knife", colorHex: "#FF9F0A", cents: 3_200, isIncome: false, date: .now),
                WidgetRecent(id: UUID(), title: "交通", symbol: "tram.fill", colorHex: "#0A84FF", cents: 1_800, isIncome: false, date: .now),
                WidgetRecent(id: UUID(), title: "零食", symbol: "cup.and.saucer.fill", colorHex: "#C7A36B", cents: 1_850, isIncome: false, date: .now),
            ]
        )
    }
}

// MARK: - Provider

enum WidgetData {
    static let container = AppGroup.makeContainer(cloudSync: false)

    static func load() -> SummaryEntry {
        let context = ModelContext(container)
        let settings = AppSettings.shared
        let ledgerID = settings.currentLedgerID
        let cal = Calendar.current
        let month = Periods.month(containing: .now)
        let weekStart = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: .now)) ?? month.start
        let start = min(month.start, weekStart)
        let end = month.end

        let descriptor = FetchDescriptor<Record>(
            predicate: #Predicate<Record> { $0.date >= start && $0.date < end && $0.ledgerID == ledgerID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        let monthRecords = records.filter { month.contains($0.date) && $0.date < month.end }
        let summary = Stats.summary(monthRecords)
        let today = Stats.summary(records.filter { cal.isDateInToday($0.date) })

        let budgets = (try? context.fetch(FetchDescriptor<Budget>(predicate: #Predicate<Budget> { $0.ledgerID == ledgerID }))) ?? []
        let budget = budgets.first { $0.category == nil }?.amountCents ?? 0

        let top = Stats.slices(monthRecords, kind: .expense).prefix(4).map {
            WidgetCategory(name: $0.name, symbol: $0.symbol, colorHex: categoryHex(for: $0.id, in: monthRecords), cents: $0.cents)
        }

        let daily = Stats.dailyTotals(records)
        let week = (0..<7).reversed().compactMap { offset -> WidgetDay? in
            guard let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: .now)) else { return nil }
            return WidgetDay(date: day, cents: daily[day]?.expense ?? 0)
        }

        let recent = records.filter { $0.kind != .transfer && $0.date <= .now }.prefix(4).map {
            WidgetRecent(id: $0.uuid, title: $0.note.isEmpty ? $0.displayTitle : "\($0.displayTitle) · \($0.note)",
                         symbol: $0.displaySymbol, colorHex: $0.category?.colorHex ?? "#8E8E93",
                         cents: $0.baseAmountCents, isIncome: $0.kind == .income, date: $0.date)
        }

        return SummaryEntry(
            date: .now,
            currency: settings.baseCurrency,
            monthTitle: Periods.title(month, kind: .month),
            monthExpense: summary.expense,
            monthIncome: summary.income,
            todayExpense: today.expense,
            budget: budget,
            top: Array(top),
            week: week,
            recent: Array(recent)
        )
    }

    private static func categoryHex(for id: UUID, in records: [Record]) -> String {
        records.first { $0.category?.uuid == id }?.category?.colorHex ?? "#8E8E93"
    }
}

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        completion(context.isPreview ? .placeholder : WidgetData.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let entry = WidgetData.load()
        let cal = Calendar.current
        let nextHour = cal.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1_800)
        let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? nextHour
        completion(Timeline(entries: [entry], policy: .after(min(nextHour, midnight))))
    }
}

// MARK: - Widget

struct SummaryWidget: Widget {
    let kind = "MoonMoneySummary"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SummaryProvider()) { entry in
            SummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("月度概览")
        .description("本月支出、预算进度与快捷记账。")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct SummaryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SummaryEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: Text("本月 \(money(entry.monthExpense))")
        case .systemMedium: medium
        case .systemLarge: large
        default: small
        }
    }

    // MARK: Home screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "moon.stars.fill").foregroundStyle(.yellow)
                Text("\(entry.monthTitle)支出").font(.caption).foregroundStyle(.white.opacity(0.8))
                Spacer()
            }
            Text(money(entry.monthExpense))
                .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("今日 \(money(entry.todayExpense))")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
            Spacer(minLength: 0)
            if entry.budget > 0 {
                budgetBar
                Text(entry.budgetRemaining >= 0 ? "预算剩余 \(money(entry.budgetRemaining))" : "超支 \(money(-entry.budgetRemaining))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .containerBackground(for: .widget) { background }
        .widgetURL(URL(string: "moonmoney://add"))
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(entry.monthTitle)支出").font(.caption).foregroundStyle(.white.opacity(0.8))
                Text(money(entry.monthExpense))
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if entry.budget > 0 { budgetBar }
                Text("收入 \(money(entry.monthIncome))").font(.caption2).foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 0)
                quickButtons
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(entry.top.prefix(3), id: \.self) { item in
                    categoryRow(item)
                }
                if entry.top.isEmpty {
                    Text("本月还没有支出").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .containerBackground(for: .widget) { background }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.monthTitle)支出").font(.caption).foregroundStyle(.white.opacity(0.8))
                    Text(money(entry.monthExpense))
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("今日").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    Text(money(entry.todayExpense)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(.white)
                }
            }
            if entry.budget > 0 { budgetBar }

            Chart(entry.week) { day in
                BarMark(x: .value("日", day.date, unit: .day), y: .value("支出", Double(day.cents) / 100))
                    .foregroundStyle(.white.opacity(Calendar.current.isDateInToday(day.date) ? 1 : 0.55))
                    .cornerRadius(3)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: entry.week.map(\.date)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.zh("EEEEE")).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
            .frame(height: 70)

            VStack(spacing: 8) {
                ForEach(entry.recent.prefix(3)) { item in
                    HStack(spacing: 8) {
                        glyph(item.symbol, hex: item.colorHex)
                        Text(item.title).font(.caption).foregroundStyle(.white).lineLimit(1)
                        Spacer()
                        Text((item.isIncome ? "+" : "-") + money(item.cents))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            Spacer(minLength: 0)
            quickButtons
        }
        .containerBackground(for: .widget) { background }
    }

    // MARK: Lock screen

    private var circular: some View {
        Gauge(value: min(entry.budgetRatio, 1)) {
            Image(systemName: "moon.stars.fill")
        } currentValueLabel: {
            Text(entry.budget > 0 ? "\(Int(entry.budgetRatio * 100))%" : Money.compact(entry.todayExpense))
                .font(.system(.caption, design: .rounded).monospacedDigit())
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "moonmoney://add"))
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("MoonMoney", systemImage: "moon.stars.fill").font(.caption2.weight(.semibold)).widgetAccentable()
            Text("本月 \(money(entry.monthExpense))").font(.headline.monospacedDigit())
            Text(entry.budget > 0 ? "预算剩余 \(money(entry.budgetRemaining))" : "今日 \(money(entry.todayExpense))")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "moonmoney://add"))
    }

    // MARK: Pieces

    private var background: some View {
        LinearGradient(colors: [Color(hex: "#2B1E6B"), Color(hex: "#6C48E6"), Color(hex: "#B05FC9")],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var budgetBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule()
                    .fill(entry.budgetRatio >= 1 ? Color.red : (entry.budgetRatio > 0.8 ? .orange : .white))
                    .frame(width: max(6, geo.size.width * min(entry.budgetRatio, 1)))
            }
        }
        .frame(height: 6)
    }

    private var quickButtons: some View {
        HStack(spacing: 6) {
            quickButton("支出", symbol: "minus", url: "moonmoney://add?kind=expense")
            quickButton("收入", symbol: "plus", url: "moonmoney://add?kind=income")
            quickButton("AI", symbol: "sparkles", url: "moonmoney://ai")
        }
    }

    private func quickButton(_ title: String, symbol: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.white.opacity(0.2), in: .capsule)
        }
    }

    private func categoryRow(_ item: WidgetCategory) -> some View {
        let share = entry.monthExpense > 0 ? Double(item.cents) / Double(entry.monthExpense) : 0
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                glyph(item.symbol, hex: item.colorHex)
                Text(item.name).font(.caption).foregroundStyle(.white)
                Spacer()
                Text(Money.compact(item.cents)).font(.caption.monospacedDigit()).foregroundStyle(.white)
            }
            GeometryReader { geo in
                Capsule().fill(Color(hex: item.colorHex))
                    .frame(width: max(4, geo.size.width * share))
            }
            .frame(height: 3)
        }
    }

    private func glyph(_ symbol: String, hex: String) -> some View {
        SymbolGlyph(symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Color(hex: hex), in: .circle)
    }

    private func money(_ cents: Int) -> String {
        Money.format(cents, code: entry.currency)
    }
}
