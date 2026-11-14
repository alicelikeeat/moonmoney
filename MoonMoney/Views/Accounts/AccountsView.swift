import Charts
import SwiftData
import SwiftUI

struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Query(sort: \Account.order) private var accounts: [Account]
    @State private var editing: Account?
    @State private var creating = false
    @State private var showArchived = false

    var body: some View {
        let visible = accounts.filter { showArchived || !$0.isArchived }
        // Each balance scans that account's records; compute once per render.
        let balances = Dictionary(accounts.map { ($0.uuid, $0.balanceCents) }, uniquingKeysWith: { a, _ in a })
        let totals = netWorth(accounts.filter { !$0.isArchived && $0.includeInNetWorth }, balances: balances)

        NavigationStack {
            List {
                Group {
                    NetWorthCard(assets: totals.assets, liabilities: totals.liabilities)
                        .plainListRow(top: 8, bottom: 8)

                    if accounts.contains(where: { !($0.records ?? []).isEmpty }) {
                        NetWorthTrend(accounts: accounts.filter { !$0.isArchived && $0.includeInNetWorth })
                            .plainListRow(top: 0, bottom: 8)
                    }

                    ForEach(AccountType.allCases) { type in
                        let group = visible.filter { $0.type == type }
                        if !group.isEmpty {
                            Section {
                                ForEach(group) { account in
                                    NavigationLink(value: account) {
                                        AccountRow(account: account, balance: balances[account.uuid] ?? 0)
                                    }
                                    .swipeActions {
                                        Button {
                                            editing = account
                                        } label: {
                                            Label("编辑", systemImage: "pencil")
                                        }
                                        .tint(.orange)
                                        Button {
                                            account.isArchived.toggle()
                                            try? context.save()
                                        } label: {
                                            Label(account.isArchived ? "取消归档" : "归档", systemImage: "archivebox")
                                        }
                                        .tint(.gray)
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            router.newRecord(kind: .transfer, account: account)
                                        } label: {
                                            Label("转账", systemImage: "arrow.left.arrow.right")
                                        }
                                        .tint(.blue)
                                    }
                                }
                                .onMove { indices, destination in
                                    move(group, from: indices, to: destination)
                                }
                            } header: {
                                HStack {
                                    Text(type.title)
                                    Spacer()
                                    let sum = group.filter { !$0.isArchived }.reduce(0) {
                                        $0 + AppSettings.shared.convertToBase(balances[$1.uuid] ?? 0, from: $1.currencyCode)
                                    }
                                    Text(Money.format(sum)).monospacedDigit()
                                }
                                .textCase(nil)
                            }
                        }
                    }

                    if accounts.isEmpty {
                        ContentUnavailableView("还没有账户", systemImage: "wallet.bifold",
                                               description: Text("添加现金、银行卡、信用卡或网络账户，余额会随记账自动变化。"))
                            .plainListRow()
                    }
                }
                .listRowBackground(GlassRowBackground())
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(tint: .teal) }
            .navigationTitle("资产")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Toggle("显示已归档", systemImage: "archivebox", isOn: $showArchived)
                        EditButton()
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("转账", systemImage: "arrow.left.arrow.right") {
                        router.newRecord(kind: .transfer)
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加账户", systemImage: "plus") { creating = true }
                        .buttonStyle(.glassProminent)
                }
            }
            .navigationDestination(for: Account.self) { account in
                AccountDetailView(account: account)
            }
            .navigationDestination(for: Record.self) { record in
                RecordDetailView(record: record)
            }
            .sheet(isPresented: $creating) {
                AccountEditor(account: nil)
            }
            .sheet(item: $editing) { account in
                AccountEditor(account: account)
            }
        }
    }

    private func netWorth(_ accounts: [Account], balances: [UUID: Int]) -> (assets: Int, liabilities: Int) {
        var assets = 0
        var liabilities = 0
        for account in accounts {
            let balance = AppSettings.shared.convertToBase(balances[account.uuid] ?? 0, from: account.currencyCode)
            if balance >= 0 { assets += balance } else { liabilities += -balance }
        }
        return (assets, liabilities)
    }

    private func move(_ group: [Account], from source: IndexSet, to destination: Int) {
        var reordered = group
        reordered.move(fromOffsets: source, toOffset: destination)
        let baseOrder = group.map(\.order).min() ?? 0
        for (index, account) in reordered.enumerated() {
            account.order = baseOrder + index
        }
        try? context.save()
    }
}

struct NetWorthCard: View {
    let assets: Int
    let liabilities: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("净资产").font(Font.skin(.subheadline)).foregroundStyle(.secondary)
            Text(Money.format(assets - liabilities))
                .font(.money(38))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("总资产").font(Font.skin(.caption)).foregroundStyle(.secondary)
                    Text(Money.format(assets)).font(Font.skin(.subheadline).weight(.semibold).monospacedDigit())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text("总负债").font(Font.skin(.caption)).foregroundStyle(.secondary)
                    Text(Money.format(liabilities))
                        .font(Font.skin(.subheadline).weight(.semibold).monospacedDigit())
                        .foregroundStyle(liabilities > 0 ? Color.expense : Color.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if assets + liabilities > 0 {
                GeometryReader { geo in
                    let ratio = Double(assets) / Double(assets + liabilities)
                    HStack(spacing: 3) {
                        Capsule().fill(Color.income.gradient).frame(width: max(4, (geo.size.width - 3) * ratio))
                        Capsule().fill(Color.expense.gradient)
                    }
                }
                .frame(height: 8)
            }
        }
        .glassCard(cornerRadius: 32, padding: 20)
    }
}

struct AccountRow: View {
    let account: Account
    let balance: Int

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(symbol: account.symbol, color: account.color, size: 40, filled: true, image: account.iconImage)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.name).font(Font.skin(.body).weight(.medium))
                    if account.isArchived {
                        Text("已归档").font(Font.skin(.caption2)).foregroundStyle(.secondary)
                    }
                    if account.currencyCode != AppSettings.shared.baseCurrency {
                        Text(account.currencyCode)
                            .font(Font.skin(.caption2).weight(.semibold))
                            .padding(.horizontal, 5)
                            .background(.quaternary, in: .capsule)
                    }
                }
                if account.type == .credit {
                    creditSubtitle
                } else if !account.note.isEmpty {
                    Text(account.note).font(Font.skin(.caption)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(Money.format(balance, code: account.currencyCode))
                .font(Font.skin(.body).weight(.semibold).monospacedDigit())
                .foregroundStyle(balance < 0 ? Color.expense : Color.primary)
        }
        .padding(.vertical, 2)
        .opacity(account.isArchived ? 0.55 : 1)
    }

    @ViewBuilder
    private var creditSubtitle: some View {
        HStack(spacing: 8) {
            if account.creditLimitCents > 0 {
                Text("可用 \(Money.format(account.availableCreditCents, code: account.currencyCode))")
            }
            if let due = account.nextDueDate {
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: due).day ?? 0
                Text(days == 0 ? "今天还款" : "\(days) 天后还款")
                    .foregroundStyle(days <= 3 ? Color.orange : Color.secondary)
            }
        }
        .font(Font.skin(.caption))
        .foregroundStyle(.secondary)
    }
}

// MARK: - Detail

struct AccountDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Bindable var account: Account
    @State private var editing = false
    @State private var adjusting = false
    @State private var adjustText = ""

    private var allRecords: [Record] {
        ((account.records ?? []) + (account.incomingTransfers ?? []))
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        let records = allRecords
        List {
            Group {
                header
                    .plainListRow(top: 8, bottom: 8)

                if records.count > 1 {
                    trend.plainListRow()
                }

                ForEach(Stats.groupedByDay(Array(records.prefix(300))), id: \.day) { group in
                    Section {
                        ForEach(group.records) { record in
                            NavigationLink(value: record) {
                                RecordRow(record: record)
                            }
                        }
                    } header: {
 SectionTitle(group.day.dayHeaderTitle)
 }
                }
            }
            .listRowBackground(GlassRowBackground())
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(tint: account.color) }
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("编辑账户", systemImage: "pencil") { editing = true }
                    Button("调整余额", systemImage: "slider.horizontal.3") {
                        adjustText = Money.plain(account.balanceCents).replacingOccurrences(of: ",", with: "")
                        adjusting = true
                    }
                    Button("转账", systemImage: "arrow.left.arrow.right") {
                        router.newRecord(kind: .transfer, account: account)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("记一笔", systemImage: "plus") {
                    router.newRecord(account: account)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .sheet(isPresented: $editing) {
            AccountEditor(account: account, allowsDelete: false)
        }
        .alert("调整余额", isPresented: $adjusting) {
            TextField("当前实际余额", text: $adjustText)
                .keyboardType(.numbersAndPunctuation)
            Button("取消", role: .cancel) {}
            Button("确定") { applyAdjustment() }
        } message: {
            Text("将直接修正账户余额，不会产生收支记录。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CategoryIcon(symbol: account.symbol, color: account.color, size: 48, filled: true, image: account.iconImage)
                VStack(alignment: .leading) {
                    Text(account.type.title).font(Font.skin(.caption)).foregroundStyle(.secondary)
                    Text(account.type == .credit ? "当前欠款" : "当前余额").font(Font.skin(.subheadline))
                }
            }
            Text(Money.format(account.type == .credit ? -account.balanceCents : account.balanceCents, code: account.currencyCode))
                .font(.money(36))
                .contentTransition(.numericText())
            if account.type == .credit {
                HStack {
                    info("额度", Money.format(account.creditLimitCents, code: account.currencyCode))
                    info("可用", Money.format(account.availableCreditCents, code: account.currencyCode))
                    if account.billingDay > 0 { info("账单日", "每月\(account.billingDay)日") }
                    if account.dueDay > 0 { info("还款日", "每月\(account.dueDay)日") }
                }
                if account.creditLimitCents > 0 {
                    ProgressCapsule(
                        value: Double(max(0, -account.balanceCents)) / Double(account.creditLimitCents),
                        tint: .orange
                    )
                }
            }
        }
        .glassCard(cornerRadius: 30, tint: account.color.opacity(0.1))
    }

    private func info(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Font.skin(.caption2)).foregroundStyle(.secondary)
            Text(value).font(Font.skin(.caption).weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trend: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days: [Date] = (0..<30).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let cutoffs = days.map { (cal.date(byAdding: .day, value: 1, to: $0) ?? $0).addingTimeInterval(-1) }
        let series = account.balanceSeries(at: cutoffs)
        let points = zip(days, series).map { BalancePoint(date: $0, value: Double($1) / 100) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("近 30 天余额").font(Font.skin(.subheadline).weight(.semibold))
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("日期", point.date, unit: .day), y: .value("余额", point.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(account.color)
                    AreaMark(x: .value("日期", point.date, unit: .day), y: .value("余额", point.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(account.color.opacity(0.15).gradient)
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis(.hidden)
            .frame(height: 90)
        }
        .glassCard()
    }

    private func applyAdjustment() {
        guard let value = Decimal(string: adjustText.replacingOccurrences(of: ",", with: ""),
                                  locale: Locale(identifier: "en_US_POSIX")) else { return }
        let target = Money.cents(value)
        account.initialBalanceCents += target - account.balanceCents
        try? context.save()
        Haptics.success()
    }
}

struct BalancePoint: Identifiable {
    var id: Date { date }
    let date: Date
    let value: Double
}

/// Net worth at each of the last 12 month-ends.
struct NetWorthTrend: View {
    let accounts: [Account]

    /// One sorted sweep per account instead of 12 full scans.
    private func monthlyPoints(from thisMonth: Date, calendar cal: Calendar) -> [BalancePoint] {
        let months: [Date] = (0..<12).reversed().compactMap { cal.date(byAdding: .month, value: -$0, to: thisMonth) }
        let cutoffs = months.map { min((cal.date(byAdding: .month, value: 1, to: $0) ?? $0).addingTimeInterval(-1), .now) }
        var totals = Array(repeating: 0, count: months.count)
        for account in accounts {
            for (index, balance) in account.balanceSeries(at: cutoffs).enumerated() {
                totals[index] += AppSettings.shared.convertToBase(balance, from: account.currencyCode)
            }
        }
        return zip(months, totals).map { BalancePoint(date: $0, value: Double($1) / 100) }
    }

    var body: some View {
        let cal = Calendar.current
        let thisMonth = cal.dateInterval(of: .month, for: .now)?.start ?? .now
        let points = monthlyPoints(from: thisMonth, calendar: cal)
        let first = points.first?.value ?? 0
        let last = points.last?.value ?? 0

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("净资产走势").font(Font.skin(.subheadline).weight(.semibold))
                Spacer()
                Text("近 12 个月 \(last >= first ? "+" : "")\(Money.format(Money.cents(last - first)))")
                    .font(Font.skin(.caption).monospacedDigit())
                    .foregroundStyle(last >= first ? Color.income : Color.expense)
            }
            Chart(points) { point in
                AreaMark(x: .value("月份", point.date, unit: .month), y: .value("净资产", point.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [Color.teal.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("月份", point.date, unit: .month), y: .value("净资产", point.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.teal)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) { Text(Money.compact(Int(amount * 100))) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: points.enumerated().filter { $0.offset % 3 == 2 }.map(\.element.date)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) { Text(date.zh("M")) }
                    }
                }
            }
            .frame(height: 140)
        }
        .glassCard(cornerRadius: 26)
    }
}
