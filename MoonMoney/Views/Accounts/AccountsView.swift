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
        let totals = netWorth(accounts.filter { !$0.isArchived && $0.includeInNetWorth })

        NavigationStack {
            List {
                NetWorthCard(assets: totals.assets, liabilities: totals.liabilities)
                    .plainListRow(top: 8, bottom: 8)

                ForEach(AccountType.allCases) { type in
                    let group = visible.filter { $0.type == type }
                    if !group.isEmpty {
                        Section {
                            ForEach(group) { account in
                                NavigationLink(value: account) {
                                    AccountRow(account: account)
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
                                    $0 + AppSettings.shared.convertToBase($1.balanceCents, from: $1.currencyCode)
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

    private func netWorth(_ accounts: [Account]) -> (assets: Int, liabilities: Int) {
        var assets = 0
        var liabilities = 0
        for account in accounts {
            let balance = AppSettings.shared.convertToBase(account.balanceCents, from: account.currencyCode)
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
            Text("净资产").font(.subheadline).foregroundStyle(.secondary)
            Text(Money.format(assets - liabilities))
                .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("总资产").font(.caption).foregroundStyle(.secondary)
                    Text(Money.format(assets)).font(.subheadline.weight(.semibold).monospacedDigit())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text("总负债").font(.caption).foregroundStyle(.secondary)
                    Text(Money.format(liabilities))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
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

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(symbol: account.symbol, color: account.color, size: 40, filled: true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.name).font(.body.weight(.medium))
                    if account.isArchived {
                        Text("已归档").font(.caption2).foregroundStyle(.secondary)
                    }
                    if account.currencyCode != AppSettings.shared.baseCurrency {
                        Text(account.currencyCode)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .background(.quaternary, in: .capsule)
                    }
                }
                if account.type == .credit {
                    creditSubtitle
                } else if !account.note.isEmpty {
                    Text(account.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(Money.format(account.balanceCents, code: account.currencyCode))
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(account.balanceCents < 0 ? Color.expense : Color.primary)
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
        .font(.caption)
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
            header
                .plainListRow(top: 8, bottom: 8)

            if records.count > 1 {
                trend.plainListRow()
            }

            ForEach(Stats.groupedByDay(Array(records.prefix(300))), id: \.day) { group in
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
                CategoryIcon(symbol: account.symbol, color: account.color, size: 48, filled: true)
                VStack(alignment: .leading) {
                    Text(account.type.title).font(.caption).foregroundStyle(.secondary)
                    Text(account.type == .credit ? "当前欠款" : "当前余额").font(.subheadline)
                }
            }
            Text(Money.format(account.type == .credit ? -account.balanceCents : account.balanceCents, code: account.currencyCode))
                .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
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
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trend: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let points: [BalancePoint] = (0..<30).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today),
                  let end = cal.date(byAdding: .day, value: 1, to: day) else { return nil }
            return BalancePoint(date: day, value: Double(account.balanceCents(asOf: end.addingTimeInterval(-1))) / 100)
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("近 30 天余额").font(.subheadline.weight(.semibold))
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

private struct BalancePoint: Identifiable {
    var id: Date { date }
    let date: Date
    let value: Double
}
