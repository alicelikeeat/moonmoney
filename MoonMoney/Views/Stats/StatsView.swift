import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var periodKind: PeriodKind = .month
    @State private var anchor = Date.now
    @State private var kind: RecordKind = .expense

    var body: some View {
        let interval = Periods.interval(periodKind, containing: anchor)
        let previous = Periods.shift(interval, kind: periodKind, by: -1)
        NavigationStack {
            StatsContent(
                interval: interval,
                previous: previous,
                periodKind: periodKind,
                kind: kind,
                ledgerID: settings.currentLedgerID
            )
            .id("\(interval.start.timeIntervalSince1970)-\(periodKind.rawValue)-\(settings.currentLedgerID?.uuidString ?? "")")
            .safeAreaInset(edge: .top, spacing: 0) {
                periodBar(interval)
            }
            .navigationTitle("统计")
            .navigationSubtitle(Periods.title(interval, kind: periodKind))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("类型", selection: $kind) {
                        Text("支出").tag(RecordKind.expense)
                        Text("收入").tag(RecordKind.income)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }
            .navigationDestination(for: CategorySlice.self) { slice in
                CategoryRecordsView(slice: slice, interval: interval, kind: kind, ledgerID: settings.currentLedgerID)
            }
            .navigationDestination(for: Record.self) { record in
                RecordDetailView(record: record)
            }
        }
    }

    private func periodBar(_ interval: DateInterval) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    move(interval, -1)
                } label: {
                    Image(systemName: "chevron.left").frame(width: 20, height: 20)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)

                Picker("周期", selection: $periodKind.animation(.smooth)) {
                    ForEach(PeriodKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    move(interval, 1)
                } label: {
                    Image(systemName: "chevron.right").frame(width: 20, height: 20)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(interval.contains(.now))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func move(_ interval: DateInterval, _ value: Int) {
        Haptics.tap()
        withAnimation(.smooth) {
            anchor = Periods.shift(interval, kind: periodKind, by: value).start.addingTimeInterval(3_600)
        }
    }
}

private struct StatsContent: View {
    @Query private var records: [Record]
    let interval: DateInterval
    let previous: DateInterval
    let periodKind: PeriodKind
    let kind: RecordKind

    @State private var selectedDate: Date?
    @State private var selectedAngle: Int?

    init(interval: DateInterval, previous: DateInterval, periodKind: PeriodKind, kind: RecordKind, ledgerID: UUID?) {
        self.interval = interval
        self.previous = previous
        self.periodKind = periodKind
        self.kind = kind
        let start = previous.start
        let end = interval.end
        _records = Query(
            filter: #Predicate<Record> { $0.date >= start && $0.date < end && $0.ledgerID == ledgerID },
            sort: \Record.date,
            order: .reverse
        )
    }

    var body: some View {
        let current = records.filter { interval.contains($0.date) && $0.date < interval.end }
        let prior = records.filter { $0.date >= previous.start && $0.date < previous.end }
        let summary = Stats.summary(current)
        let priorSummary = Stats.summary(prior)
        let slices = Stats.slices(current, kind: kind)
        let buckets = Stats.buckets(current, interval: interval, kind: periodKind)
        let total = kind == .expense ? summary.expense : summary.income
        let priorTotal = kind == .expense ? priorSummary.expense : priorSummary.income

        ScrollView {
            VStack(spacing: 16) {
                overview(summary: summary, total: total, priorTotal: priorTotal)
                trendCard(buckets)
                if slices.isEmpty {
                    ContentUnavailableView("暂无\(kind.title)数据", systemImage: "chart.pie",
                                           description: Text("换个时间段看看，或者先记一笔。"))
                        .glassCard()
                } else {
                    donutCard(slices, total: total)
                    rankingCard(slices)
                    topRecordsCard(current)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background { AmbientBackground(tint: kind.tint) }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    // MARK: Overview

    private func overview(summary: PeriodSummary, total: Int, priorTotal: Int) -> some View {
        let change = Stats.percentChange(current: total, previous: priorTotal)
        let days = Periods.elapsedDays(in: interval)
        return VStack(alignment: .leading, spacing: 14) {
            Text("总\(kind.title)").font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(Money.format(total))
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Spacer()
                if let change {
                    let up = change >= 0
                    Label("\(up ? "+" : "")\(change.formatted(.percent.precision(.fractionLength(0...1))))",
                          systemImage: up ? "arrow.up.right" : "arrow.down.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(kind == .expense ? (up ? Color.expense : Color.income) : (up ? Color.income : Color.expense))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: .capsule)
                }
            }
            HStack(spacing: 0) {
                stat("日均", Money.format(total / max(days, 1)))
                stat("笔数", "\(Stats.counted(records.filter { interval.contains($0.date) && $0.date < interval.end }).filter { $0.kind == kind }.count)")
                stat(kind == .expense ? "收入" : "支出", Money.format(kind == .expense ? summary.income : summary.expense))
                stat("结余", Money.signed(summary.net))
            }
        }
        .glassCard(cornerRadius: 30)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Trend

    private func trendCard(_ buckets: [TimeBucket]) -> some View {
        let unit: Calendar.Component = periodKind == .year ? .month : .day
        let values = buckets.map { kind == .expense ? $0.expense : $0.income }
        let nonZero = values.filter { $0 > 0 }
        let average = nonZero.isEmpty ? 0 : Double(values.reduce(0, +)) / Double(max(buckets.count, 1)) / 100
        let selectedBucket = selectedDate.flatMap { date in
            buckets.first { Calendar.current.isDate($0.date, equalTo: date, toGranularity: unit) }
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("趋势").font(.headline)
                Spacer()
                if let selectedBucket {
                    let value = kind == .expense ? selectedBucket.expense : selectedBucket.income
                    Text("\(selectedBucket.date.zh(periodKind == .year ? "MMMM" : "MMMd")) \(Money.format(value))")
                        .font(.footnote.monospacedDigit().weight(.medium))
                        .foregroundStyle(kind.tint)
                } else {
                    Text("平均 \(Money.format(Int(average * 100)))")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Chart {
                ForEach(buckets) { bucket in
                    let value = Double(kind == .expense ? bucket.expense : bucket.income) / 100
                    BarMark(
                        x: .value("日期", bucket.date, unit: unit),
                        y: .value("金额", value)
                    )
                    .foregroundStyle(kind.tint.gradient)
                    .cornerRadius(4)
                    .opacity(selectedBucket == nil || selectedBucket?.date == bucket.date ? 1 : 0.35)
                }
                if average > 0 {
                    RuleMark(y: .value("平均", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(Money.compact(Int(amount * 100)))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: axisDates(buckets)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(date))
                        }
                    }
                }
            }
            .frame(height: 190)
        }
        .glassCard()
    }

    private func axisDates(_ buckets: [TimeBucket]) -> [Date] {
        switch periodKind {
        case .year, .week: buckets.map(\.date)
        case .month: buckets.enumerated().filter { $0.offset % 7 == 0 }.map(\.element.date)
        }
    }

    private func axisLabel(_ date: Date) -> String {
        switch periodKind {
        case .year: date.zh("MMM")
        case .week: date.zh("EEEEE")
        case .month: date.zh("d")
        }
    }

    // MARK: Donut

    private func donutCard(_ slices: [CategorySlice], total: Int) -> some View {
        let selected = selectedSlice(slices)
        return VStack(alignment: .leading, spacing: 12) {
            Text("构成").font(.headline)
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("金额", slice.cents),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(5)
                .foregroundStyle(slice.color.gradient)
                .opacity(selected == nil || selected?.id == slice.id ? 1 : 0.3)
            }
            .chartAngleSelection(value: $selectedAngle)
            .chartBackground { proxy in
                GeometryReader { geo in
                    if let anchor = proxy.plotFrame {
                        let frame = geo[anchor]
                        VStack(spacing: 4) {
                            if let selected {
                                Image(systemName: selected.symbol)
                                    .font(.title2)
                                    .foregroundStyle(selected.color)
                                Text(selected.name).font(.subheadline.weight(.semibold))
                                Text(Money.format(selected.cents))
                                    .font(.footnote.monospacedDigit())
                                Text(selected.share.formatted(.percent.precision(.fractionLength(1))))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(slices.count) 个分类").font(.caption).foregroundStyle(.secondary)
                                Text(Money.format(total))
                                    .font(.headline.monospacedDigit())
                            }
                        }
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(height: 240)
            .sensoryFeedback(.selection, trigger: selected?.id)

            // Legend
            FlowLegend(slices: Array(slices.prefix(8)))
        }
        .glassCard()
    }

    private func selectedSlice(_ slices: [CategorySlice]) -> CategorySlice? {
        guard let selectedAngle else { return nil }
        var cumulative = 0
        for slice in slices {
            cumulative += slice.cents
            if selectedAngle <= cumulative { return slice }
        }
        return nil
    }

    // MARK: Ranking

    private func rankingCard(_ slices: [CategorySlice]) -> some View {
        let maxCents = slices.first?.cents ?? 1
        return VStack(alignment: .leading, spacing: 4) {
            Text("分类排行").font(.headline).padding(.bottom, 8)
            ForEach(slices) { slice in
                NavigationLink(value: slice) {
                    HStack(spacing: 12) {
                        CategoryIcon(symbol: slice.symbol, color: slice.color, size: 36)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(slice.name).font(.subheadline.weight(.medium))
                                Text(slice.share.formatted(.percent.precision(.fractionLength(1))))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Money.format(slice.cents))
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                            }
                            ProgressCapsule(value: Double(slice.cents) / Double(max(maxCents, 1)), tint: slice.color, height: 6)
                        }
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .glassCard()
    }

    // MARK: Top records

    private func topRecordsCard(_ current: [Record]) -> some View {
        let top = Stats.counted(current)
            .filter { $0.kind == kind }
            .sorted { $0.baseAmountCents > $1.baseAmountCents }
            .prefix(5)
        return VStack(alignment: .leading, spacing: 4) {
            Text("单笔 Top 5").font(.headline).padding(.bottom, 8)
            ForEach(Array(top)) { record in
                NavigationLink(value: record) {
                    RecordRow(record: record, showDate: true)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
        }
        .glassCard()
    }
}

private struct FlowLegend: View {
    let slices: [CategorySlice]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(slices) { slice in
                HStack(spacing: 6) {
                    Circle().fill(slice.color).frame(width: 8, height: 8)
                    Text(slice.name).font(.caption).lineLimit(1)
                    Text(slice.share.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// All records of one category in a period.
struct CategoryRecordsView: View {
    let slice: CategorySlice
    @Query private var records: [Record]

    init(slice: CategorySlice, interval: DateInterval, kind: RecordKind, ledgerID: UUID?) {
        self.slice = slice
        let start = interval.start
        let end = interval.end
        let kindRaw = kind.rawValue
        _records = Query(
            filter: #Predicate<Record> {
                $0.date >= start && $0.date < end && $0.ledgerID == ledgerID && $0.kindRaw == kindRaw
            },
            sort: \Record.date,
            order: .reverse
        )
    }

    var body: some View {
        let matching = records.filter { ($0.category?.uuid ?? Self.unknown) == slice.id && !$0.excludedFromStats }
        let total = matching.reduce(0) { $0 + $1.baseAmountCents }
        List {
            Section {
                HStack(spacing: 14) {
                    CategoryIcon(symbol: slice.symbol, color: slice.color, size: 52, filled: true)
                    VStack(alignment: .leading) {
                        Text(Money.format(total))
                            .font(.title2.bold().monospacedDigit())
                        Text("\(matching.count) 笔 · 平均 \(Money.format(total / max(matching.count, 1)))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .glassCard(tint: slice.color.opacity(0.12))
                .plainListRow()
            }
            ForEach(Stats.groupedByDay(matching), id: \.day) { group in
                Section(group.day.dayHeaderTitle) {
                    ForEach(group.records) { record in
                        NavigationLink(value: record) {
                            RecordRow(record: record)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(tint: slice.color) }
        .navigationTitle(slice.name)
    }

    private static let unknown = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}
