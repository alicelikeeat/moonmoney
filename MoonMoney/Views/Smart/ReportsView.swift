import Charts
import SwiftData
import SwiftUI

struct Insight: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
    let tint: Color
}

@MainActor
enum InsightEngine {
    static func monthly(current: [Record], previous: [Record], interval: DateInterval, budgetCents: Int) -> [Insight] {
        var result: [Insight] = []
        let counted = Stats.counted(current)
        let expenses = counted.filter { $0.kind == .expense }
        let summary = Stats.summary(current)
        let prior = Stats.summary(previous)

        if let change = Stats.percentChange(current: summary.expense, previous: prior.expense) {
            let up = change >= 0
            result.append(Insight(
                symbol: up ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill",
                title: up ? "支出比上期多 \(percent(change))" : "支出比上期少 \(percent(-change))",
                detail: "本期 \(Money.format(summary.expense))，上期 \(Money.format(prior.expense))。",
                tint: up ? .expense : .income
            ))
        }

        let slices = Stats.slices(current, kind: .expense)
        if let top = slices.first {
            result.append(Insight(symbol: "crown.fill", title: "「\(top.name)」是最大开销",
                                  detail: "占总支出 \(percent(top.share))，共 \(top.count) 笔 \(Money.format(top.cents))。",
                                  tint: top.color))
        }
        let priorSlices = Dictionary(Stats.slices(previous, kind: .expense).map { ($0.name, $0.cents) }, uniquingKeysWith: +)
        if let jump = slices
            .map({ ($0, $0.cents - (priorSlices[$0.name] ?? 0)) })
            .filter({ $0.1 > 0 && (priorSlices[$0.0.name] ?? 0) > 0 })
            .max(by: { $0.1 < $1.1 }), jump.1 > 5_000 {
            result.append(Insight(symbol: "chart.line.uptrend.xyaxis", title: "「\(jump.0.name)」涨得最多",
                                  detail: "比上期多花了 \(Money.format(jump.1))。", tint: .orange))
        }

        if summary.income > 0 {
            let rate = Double(summary.income - summary.expense) / Double(summary.income)
            result.append(Insight(symbol: "banknote.fill", title: "储蓄率 \(percent(rate))",
                                  detail: rate >= 0.3 ? "很稳健，继续保持！" : (rate >= 0 ? "还有提升空间，目标可以定在 30%。" : "支出超过了收入，留意大额开销。"),
                                  tint: rate >= 0.3 ? .income : .orange))
        }

        let cal = Calendar.current
        let weekend = expenses.filter { cal.isDateInWeekend($0.date) }
        let weekday = expenses.filter { !cal.isDateInWeekend($0.date) }
        let days = Periods.days(in: DateInterval(start: interval.start, end: min(interval.end, .now)))
        let weekendDays = max(1, days.filter { cal.isDateInWeekend($0) }.count)
        let weekdayDays = max(1, days.count - weekendDays)
        let weekendAvg = weekend.reduce(0) { $0 + $1.baseAmountCents } / weekendDays
        let weekdayAvg = weekday.reduce(0) { $0 + $1.baseAmountCents } / weekdayDays
        if weekendAvg > 0 && weekdayAvg > 0 {
            let ratio = Double(weekendAvg) / Double(weekdayAvg)
            if ratio > 1.3 || ratio < 0.77 {
                result.append(Insight(symbol: "calendar", title: ratio > 1 ? "周末花钱更猛" : "工作日花得更多",
                                      detail: "周末日均 \(Money.format(weekendAvg))，工作日日均 \(Money.format(weekdayAvg))。",
                                      tint: .blue))
            }
        }

        if let biggest = expenses.max(by: { $0.baseAmountCents < $1.baseAmountCents }) {
            result.append(Insight(symbol: "exclamationmark.circle.fill", title: "最大一笔：\(biggest.displayTitle)",
                                  detail: "\(biggest.date.zh("MMMd")) \(biggest.note.isEmpty ? "" : biggest.note + " ")\(Money.format(biggest.baseAmountCents))",
                                  tint: .pink))
        }

        let notes = Dictionary(grouping: expenses.filter { !$0.note.isEmpty }, by: \.note)
        if let frequent = notes.max(by: { $0.value.count < $1.value.count }), frequent.value.count >= 3 {
            let total = frequent.value.reduce(0) { $0 + $1.baseAmountCents }
            result.append(Insight(symbol: "repeat.circle.fill", title: "「\(frequent.key)」出现了 \(frequent.value.count) 次",
                                  detail: "累计 \(Money.format(total))，小额高频最容易被忽略。", tint: .purple))
        }

        let spendDays = Set(expenses.map { cal.startOfDay(for: $0.date) })
        let noSpend = days.filter { !spendDays.contains($0) }.count
        if noSpend > 0 {
            result.append(Insight(symbol: "leaf.fill", title: "\(noSpend) 天零支出", detail: "给自己的克制点个赞。", tint: .mint))
        }

        if budgetCents > 0, interval.contains(.now) {
            let elapsed = Periods.elapsedDays(in: interval)
            let projected = summary.expense / max(elapsed, 1) * Periods.totalDays(in: interval)
            let over = projected - budgetCents
            result.append(Insight(symbol: "target", title: over > 0 ? "按当前节奏将超支 \(Money.format(over))" : "按当前节奏能守住预算",
                                  detail: "预计月底支出 \(Money.format(projected))，预算 \(Money.format(budgetCents))。",
                                  tint: over > 0 ? .expense : .income))
        }
        return result
    }

    nonisolated static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

// MARK: - Reports screen

struct ReportsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var mode = 0
    @State private var anchor = Date.now

    var body: some View {
        let kind: PeriodKind = mode == 0 ? .month : .year
        let interval = Periods.interval(kind, containing: anchor)
        let previous = Periods.shift(interval, kind: kind, by: -1)
        ReportContent(interval: interval, previous: previous, kind: kind, ledgerID: settings.currentLedgerID)
            .id("\(mode)-\(interval.start.timeIntervalSince1970)-\(settings.currentLedgerID?.uuidString ?? "")")
            .navigationTitle(mode == 0 ? "月度报告" : "年度账单")
            .navigationSubtitle(Periods.title(interval, kind: kind))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("报告", selection: $mode) {
                        Text("月报").tag(0)
                        Text("年报").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("上一期", systemImage: "chevron.left") {
                        anchor = Periods.shift(interval, kind: kind, by: -1).start.addingTimeInterval(3_600)
                    }
                    Spacer()
                    Button("下一期", systemImage: "chevron.right") {
                        anchor = Periods.shift(interval, kind: kind, by: 1).start.addingTimeInterval(3_600)
                    }
                    .disabled(interval.contains(.now))
                }
            }
    }
}

private struct ReportContent: View {
    @Query private var records: [Record]
    @Query private var budgets: [Budget]
    let interval: DateInterval
    let previous: DateInterval
    let kind: PeriodKind

    @State private var commentary: String?
    @State private var loadingAI = false
    @State private var poster: Image?

    init(interval: DateInterval, previous: DateInterval, kind: PeriodKind, ledgerID: UUID?) {
        self.interval = interval
        self.previous = previous
        self.kind = kind
        let start = previous.start
        let end = interval.end
        _records = Query(filter: #Predicate<Record> { $0.date >= start && $0.date < end && $0.ledgerID == ledgerID },
                         sort: \Record.date)
        _budgets = Query(filter: #Predicate<Budget> { $0.ledgerID == ledgerID })
    }

    var body: some View {
        let current = records.filter { $0.date >= interval.start && $0.date < interval.end }
        let prior = records.filter { $0.date >= previous.start && $0.date < previous.end }
        let budget = (budgets.first { $0.category == nil }?.amountCents ?? 0) * (kind == .year ? 12 : 1)
        let insights = InsightEngine.monthly(current: current, previous: prior, interval: interval, budgetCents: budget)
        let summary = Stats.summary(current)

        ScrollView {
            VStack(spacing: 16) {
                if kind == .year {
                    AnnualPoster(records: current, interval: interval)
                        .clipShape(.rect(cornerRadius: 32))
                    if let poster {
                        ShareLink(item: poster, preview: SharePreview("我的年度账单", image: poster)) {
                            Label("分享年度账单", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    }
                } else {
                    HStack(spacing: 0) {
                        metric("支出", Money.format(summary.expense), .expense)
                        metric("收入", Money.format(summary.income), .income)
                        metric("结余", Money.signed(summary.net), summary.net >= 0 ? .income : .expense)
                    }
                    .glassCard(cornerRadius: 28)
                }

                aiCard(insights: insights, summary: summary)

                // One glass surface for all insights instead of a stack of glass cards.
                if !insights.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                            if index > 0 { Divider().padding(.leading, 46) }
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: insight.symbol)
                                    .font(Font.skin(.title2))
                                    .foregroundStyle(insight.tint)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(insight.title).font(Font.skin(.headline))
                                    Text(insight.detail).font(Font.skin(.subheadline)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 12)
                        }
                    }
                    .glassCard(cornerRadius: 26, padding: 16)
                }

                if current.isEmpty {
                    ContentUnavailableView("这段时间没有记录", systemImage: "doc.text.magnifyingglass")
                        .glassCard()
                }
            }
            .padding(16)
        }
        .background { AmbientBackground(tint: .purple) }
        .task(id: interval.start) {
            if kind == .year { renderPoster(current) }
        }
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Font.skin(.caption)).foregroundStyle(.secondary)
            Text(value).font(Font.skin(.headline).monospacedDigit()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func aiCard(insights: [Insight], summary: PeriodSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI 点评", systemImage: "apple.intelligence")
                .font(Font.skin(.subheadline).weight(.semibold))
                .foregroundStyle(.purple)
            if let commentary {
                Text(commentary).font(Font.skin(.body))
            } else if loadingAI {
                HStack { ProgressView(); Text("正在分析你的账单…").foregroundStyle(.secondary) }
            } else if SmartParser.isAIAvailable {
                Button {
                    Task { await generate(insights: insights, summary: summary) }
                } label: {
                    Label("生成点评", systemImage: "sparkles")
                }
                .buttonStyle(.inCard(prominent: true))
                .tint(.purple)
            } else {
                Text("AI 点评需要支持 Apple 智能的设备（\(SmartParser.aiStatusText)）。下面的洞察由本地规则生成。")
                    .font(Font.skin(.footnote))
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard(cornerRadius: 24, tint: Color.purple.opacity(0.08))
    }

    private func generate(insights: [Insight], summary: PeriodSummary) async {
        loadingAI = true
        let facts = """
        时间：\(Periods.title(interval, kind: kind))
        总支出 \(Money.format(summary.expense))，总收入 \(Money.format(summary.income))，共 \(summary.count) 笔。
        \(insights.map { "\($0.title)：\($0.detail)" }.joined(separator: "\n"))
        """
        let text = await SmartParser.commentary(for: facts)
        withAnimation(.smooth) {
            commentary = text ?? "暂时无法生成点评，请稍后再试。"
            loadingAI = false
        }
    }

    private func renderPoster(_ current: [Record]) {
        let renderer = ImageRenderer(content: AnnualPoster(records: current, interval: interval).frame(width: 390))
        renderer.scale = 3
        if let image = renderer.uiImage {
            poster = Image(uiImage: image)
        }
    }
}

/// The annual report card. Uses plain gradients so it renders into a shareable image.
struct AnnualPoster: View {
    let records: [Record]
    let interval: DateInterval

    var body: some View {
        let summary = Stats.summary(records)
        let slices = Stats.slices(records, kind: .expense)
        let buckets = Stats.buckets(records, interval: interval, kind: .year)
        let expenses = Stats.counted(records).filter { $0.kind == .expense }
        let days = Set(records.map { Calendar.current.startOfDay(for: $0.date) }).count
        let topMonth = buckets.max { $0.expense < $1.expense }
        let biggest = expenses.max { $0.baseAmountCents < $1.baseAmountCents }

        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "moon.stars.fill")
                Text("MoonMoney · \(interval.start.zh("y")) 年度账单")
            }
            .font(Font.skin(.footnote).weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))

            VStack(alignment: .leading, spacing: 4) {
                Text("这一年你花了").font(Font.skin(.subheadline)).foregroundStyle(.white.opacity(0.8))
                Text(Money.format(summary.expense))
                    .font(.system(size: 40, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("赚了 \(Money.format(summary.income)) · 记账 \(days) 天 · \(summary.count) 笔")
                    .font(Font.skin(.footnote))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Chart(buckets) { bucket in
                BarMark(x: .value("月", bucket.date, unit: .month), y: .value("支出", Double(bucket.expense) / 100))
                    .foregroundStyle(.white.opacity(bucket.date == topMonth?.date ? 1 : 0.55))
                    .cornerRadius(3)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: buckets.map(\.date)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.zh("M")).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
            .frame(height: 110)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(slices.prefix(3).enumerated()), id: \.offset) { index, slice in
                    HStack {
                        Text("\(index + 1)").font(Font.skin(.caption).bold()).frame(width: 20, height: 20)
                            .background(.white.opacity(0.25), in: .circle)
                        SymbolGlyph(slice.symbol)
                        Text(slice.name)
                        Spacer()
                        Text(Money.format(slice.cents)).monospacedDigit()
                    }
                    .font(Font.skin(.subheadline).weight(.medium))
                    .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if let topMonth, topMonth.expense > 0 {
                    Text("最能花的月份：\(topMonth.date.zh("MMMM"))（\(Money.format(topMonth.expense))）")
                }
                if let biggest {
                    Text("最大一笔：\(biggest.displayTitle) \(Money.format(biggest.baseAmountCents))")
                }
                if summary.income > 0 {
                    Text("储蓄率：\(InsightEngine.percent(Double(summary.net) / Double(summary.income)))")
                }
            }
            .font(Font.skin(.footnote))
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: "#2B1E6B"), Color(hex: "#6C48E6"), Color(hex: "#EC78AA")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }
}
