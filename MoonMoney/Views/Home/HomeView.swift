import SwiftData
import SwiftUI

enum HomeRoute: Hashable {
    case calendar
    case budget
}

struct HomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Query(sort: \Ledger.order) private var ledgers: [Ledger]
    @State private var anchor = Date.now
    @State private var showLedgers = false

    private var currentLedger: Ledger? {
        ledgers.first { $0.uuid == settings.currentLedgerID }
    }

    var body: some View {
        let interval = Periods.month(containing: anchor)
        NavigationStack {
            MonthRecordsList(interval: interval, ledgerID: settings.currentLedgerID, anchor: $anchor)
                .id("\(settings.currentLedgerID?.uuidString ?? "-")-\(interval.start.timeIntervalSince1970)")
                .navigationTitle(currentLedger?.name ?? "明细")
                .navigationSubtitle(Periods.title(interval, kind: .month))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("账本", selection: Binding(
                                get: { settings.currentLedgerID },
                                set: { settings.currentLedgerID = $0 }
                            )) {
                                ForEach(ledgers) { ledger in
                                    Label(ledger.name, systemImage: ledger.symbol).tag(Optional(ledger.uuid))
                                }
                            }
                            Divider()
                            Button {
                                showLedgers = true
                            } label: {
                                Label("管理账本", systemImage: "books.vertical")
                            }
                        } label: {
                            Image(systemName: currentLedger?.symbol ?? "book.closed")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: HomeRoute.calendar) {
                            Image(systemName: "calendar")
                        }
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            router.newRecord()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .calendar: CalendarView()
                    case .budget: BudgetView()
                    }
                }
                .navigationDestination(for: Record.self) { record in
                    RecordDetailView(record: record)
                }
                .navigationDestination(isPresented: $showLedgers) {
                    LedgerManagerView()
                }
        }
    }
}

/// Records of one financial month, grouped by day.
struct MonthRecordsList: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Query private var records: [Record]
    @Query private var budgets: [Budget]
    @Binding var anchor: Date
    let interval: DateInterval
    let ledgerID: UUID?

    init(interval: DateInterval, ledgerID: UUID?, anchor: Binding<Date>) {
        self.interval = interval
        self.ledgerID = ledgerID
        _anchor = anchor
        let start = interval.start
        let end = interval.end
        _records = Query(
            filter: #Predicate<Record> { $0.date >= start && $0.date < end && $0.ledgerID == ledgerID },
            sort: \Record.date,
            order: .reverse
        )
        _budgets = Query(filter: #Predicate<Budget> { $0.ledgerID == ledgerID })
    }

    var body: some View {
        let summary = Stats.summary(records)
        let totalBudget = budgets.first { $0.category == nil }
        let groups = Stats.groupedByDay(records)

        List {
            MonthSummaryCard(
                interval: interval,
                summary: summary,
                budgetCents: totalBudget?.amountCents ?? 0,
                anchor: $anchor
            )
            .plainListRow(top: 8, bottom: 8)

            if records.isEmpty {
                ContentUnavailableView {
                    Label("这个月还没有记录", systemImage: "moon.zzz")
                } description: {
                    Text("点按下方「记一笔」，或对 Siri 说“用 MoonMoney 记一笔”。")
                } actions: {
                    Button("记一笔") { router.newRecord() }
                        .buttonStyle(.glassProminent)
                }
                .plainListRow()
            }

            ForEach(groups, id: \.day) { group in
                Section {
                    ForEach(group.records) { record in
                        NavigationLink(value: record) {
                            RecordRow(record: record)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(record)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                router.edit(record)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                duplicate(record)
                            } label: {
                                Label("复制", systemImage: "plus.square.on.square")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            RecordContextMenu(record: record, onDuplicate: duplicate, onDelete: delete)
                        }
                    }
                } header: {
                    DayHeader(day: group.day, records: group.records)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background { AmbientBackground() }
        .animation(.smooth, value: records.count)
    }

    private func delete(_ record: Record) {
        let id = record.uuid
        withAnimation {
            context.delete(record)
            try? context.save()
        }
        AppServices.recordDeleted(id)
        Haptics.warning()
    }

    private func duplicate(_ record: Record) {
        let copy = Record(kind: record.kind, amountCents: record.amountCents, date: .now, note: record.note,
                          category: record.category, account: record.account, ledgerID: record.ledgerID)
        copy.toAccount = record.toAccount
        copy.feeCents = record.feeCents
        copy.toAmountCents = record.toAmountCents
        copy.currencyCode = record.currencyCode
        copy.tags = record.tags
        copy.member = record.member
        context.insert(copy)
        try? context.save()
        AppServices.recordsChanged([copy], context: context)
        Haptics.success()
    }
}

struct RecordContextMenu: View {
    @Environment(Router.self) private var router
    let record: Record
    var onDuplicate: (Record) -> Void
    var onDelete: (Record) -> Void

    var body: some View {
        Button {
            router.edit(record)
        } label: {
            Label("编辑", systemImage: "pencil")
        }
        Button {
            onDuplicate(record)
        } label: {
            Label("以今天再记一笔", systemImage: "plus.square.on.square")
        }
        Button {
            record.excludedFromStats.toggle()
            try? record.modelContext?.save()
        } label: {
            Label(record.excludedFromStats ? "计入统计" : "不计入统计",
                  systemImage: record.excludedFromStats ? "chart.bar.xaxis" : "chart.bar.xaxis.ascending")
        }
        Divider()
        Button(role: .destructive) {
            onDelete(record)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }
}

// MARK: - Summary card

struct MonthSummaryCard: View {
    let interval: DateInterval
    let summary: PeriodSummary
    let budgetCents: Int
    @Binding var anchor: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(Periods.title(interval, kind: .month) + "支出")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            shift(-1)
                        } label: {
                            Image(systemName: "chevron.left").frame(width: 18, height: 18)
                        }
                        Button {
                            withAnimation(.smooth) { anchor = .now }
                        } label: {
                            Text("本月").font(.footnote.weight(.semibold))
                        }
                        .disabled(interval.contains(.now))
                        Button {
                            shift(1)
                        } label: {
                            Image(systemName: "chevron.right").frame(width: 18, height: 18)
                        }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }

            Text(Money.format(summary.expense))
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            HStack(spacing: 0) {
                metric("收入", Money.format(summary.income), color: .income)
                metric("结余", Money.signed(summary.net), color: summary.net >= 0 ? .income : .expense)
                metric("日均", Money.format(summary.expense / Periods.elapsedDays(in: interval)), color: .primary)
            }

            if budgetCents > 0 {
                NavigationLink(value: HomeRoute.budget) {
                    budgetRow
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: HomeRoute.budget) {
                    Label("设置月度预算", systemImage: "target")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
        .glassCard(cornerRadius: 32, padding: 20)
    }

    private var budgetRow: some View {
        let remaining = budgetCents - summary.expense
        let ratio = Double(summary.expense) / Double(max(budgetCents, 1))
        let days = Periods.remainingDays(in: interval)
        let tint: Color = ratio >= 1 ? .expense : (ratio > 0.8 ? .orange : .income)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(remaining >= 0 ? "预算剩余 \(Money.format(remaining))" : "已超支 \(Money.format(-remaining))",
                      systemImage: "target")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(remaining >= 0 ? Color.primary : Color.expense)
                Spacer()
                if remaining > 0 && days > 0 {
                    Text("每天可用 \(Money.format(remaining / days))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            ProgressCapsule(value: ratio, tint: tint)
        }
    }

    private func metric(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shift(_ value: Int) {
        Haptics.tap()
        withAnimation(.smooth) {
            anchor = Periods.shift(interval, kind: .month, by: value).start.addingTimeInterval(3_600)
        }
    }
}

// MARK: - Rows

struct DayHeader: View {
    let day: Date
    let records: [Record]

    var body: some View {
        let summary = Stats.summary(records)
        HStack {
            Text(day.dayHeaderTitle)
            Spacer()
            if summary.expense > 0 {
                Text("支 \(Money.format(summary.expense))")
            }
            if summary.income > 0 {
                Text("收 \(Money.format(summary.income))")
                    .foregroundStyle(Color.income)
            }
        }
        .font(.footnote.weight(.medium).monospacedDigit())
        .textCase(nil)
    }
}

struct RecordRow: View {
    let record: Record
    var showDate = false

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(symbol: record.displaySymbol, color: record.displayColor, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.displayTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if record.isRecurringInstance {
                        Image(systemName: "repeat").font(.caption2).foregroundStyle(.secondary)
                    }
                    if record.photo != nil {
                        Image(systemName: "photo").font(.caption2).foregroundStyle(.secondary)
                    }
                    if record.excludedFromStats {
                        Image(systemName: "eye.slash").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !record.sortedTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(record.sortedTags.prefix(3)) { tag in
                            Text("#\(tag.name)")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(tag.color.opacity(0.15), in: .capsule)
                                .foregroundStyle(tag.color)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                AmountText(cents: record.amountCents, kind: record.kind, code: record.currencyCode)
                if record.currencyCode != AppSettings.shared.baseCurrency {
                    Text("≈ \(Money.format(record.baseAmountCents))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(record.excludedFromStats ? 0.6 : 1)
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append(showDate ? record.date.zh("MMMd HH:mm") : record.date.zh("HH:mm"))
        if record.kind != .transfer, let account = record.account { parts.append(account.name) }
        if record.kind == .transfer && record.feeCents > 0 { parts.append("手续费 \(Money.format(record.feeCents, code: record.currencyCode))") }
        if !record.note.isEmpty { parts.append(record.note) }
        return parts.joined(separator: " · ")
    }
}
