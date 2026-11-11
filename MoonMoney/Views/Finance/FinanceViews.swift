import SwiftData
import SwiftUI

// MARK: - Savings goals

struct SavingsGoalsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavingsGoal.order) private var goals: [SavingsGoal]
    @Query private var accounts: [Account]
    @State private var editing: SavingsGoal?
    @State private var creating = false
    @State private var depositing: SavingsGoal?
    @State private var depositCents = 0
    @State private var withdraw = false

    var body: some View {
        let active = goals.filter { !$0.isArchived }
        let saved = active.reduce(0) { $0 + progressCents($1) }
        let target = active.reduce(0) { $0 + $1.targetCents }

        List {
            VStack(alignment: .leading, spacing: 8) {
                Text("已存 / 目标").font(.subheadline).foregroundStyle(.secondary)
                Text("\(Money.format(saved)) / \(Money.format(target))")
                    .font(.title2.bold().monospacedDigit())
                ProgressCapsule(value: Double(saved) / Double(max(target, 1)), tint: .orange, height: 10)
            }
            .glassCard(cornerRadius: 28, tint: Color.orange.opacity(0.08))
            .plainListRow(top: 8, bottom: 8)

            if goals.isEmpty {
                ContentUnavailableView("还没有存钱目标", systemImage: "star.circle",
                                       description: Text("旅行基金、换新手机、应急金……给每一笔钱一个去处。"))
                    .plainListRow()
            }

            ForEach(goals) { goal in
                GoalRow(goal: goal, progress: progressCents(goal))
                    .contentShape(.rect)
                    .onTapGesture { editing = goal }
                    .swipeActions(edge: .leading) {
                        if goal.accountID == nil {
                            Button {
                                depositCents = 0
                                withdraw = false
                                depositing = goal
                            } label: {
                                Label("存入", systemImage: "plus")
                            }
                            .tint(.green)
                            Button {
                                depositCents = 0
                                withdraw = true
                                depositing = goal
                            } label: {
                                Label("取出", systemImage: "minus")
                            }
                            .tint(.orange)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            context.delete(goal)
                            try? context.save()
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            goal.isArchived.toggle()
                            try? context.save()
                        } label: {
                            Label(goal.isArchived ? "恢复" : "归档", systemImage: "archivebox")
                        }
                    }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(tint: .orange) }
        .navigationTitle("存钱目标")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("新建", systemImage: "plus") { creating = true }
                    .buttonStyle(.glassProminent)
            }
        }
        .sheet(isPresented: $creating) { GoalEditor(goal: nil, nextOrder: goals.count) }
        .sheet(item: $editing) { GoalEditor(goal: $0, nextOrder: goals.count) }
        .sheet(item: $depositing) { goal in
            NavigationStack {
                Form {
                    CentsField(title: withdraw ? "取出金额" : "存入金额", cents: $depositCents)
                }
                .navigationTitle(goal.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确定", systemImage: "checkmark", role: .confirm) {
                            goal.savedCents = max(0, goal.savedCents + (withdraw ? -depositCents : depositCents))
                            try? context.save()
                            Haptics.success()
                            depositing = nil
                        }
                        .disabled(depositCents <= 0)
                    }
                }
            }
            .presentationDetents([.height(220)])
        }
    }

    private func progressCents(_ goal: SavingsGoal) -> Int {
        if let id = goal.accountID, let account = accounts.first(where: { $0.uuid == id }) {
            return max(0, AppSettings.shared.convertToBase(account.balanceCents, from: account.currencyCode))
        }
        return goal.savedCents
    }
}

private struct GoalRow: View {
    let goal: SavingsGoal
    let progress: Int

    var body: some View {
        let ratio = Double(progress) / Double(max(goal.targetCents, 1))
        HStack(spacing: 14) {
            ZStack {
                RingGauge(value: ratio, tint: goal.color, lineWidth: 6)
                SymbolGlyph(goal.symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(goal.color)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(goal.name).font(.headline)
                    if ratio >= 1 { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                }
                Text("\(Money.format(progress)) / \(Money.format(goal.targetCents)) · \(InsightEngine.percent(ratio))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let deadline = goal.deadline, ratio < 1 {
                    let months = max(1, Calendar.current.dateComponents([.month], from: .now, to: deadline).month ?? 1)
                    Text("距 \(deadline.zh("yMMMd")) 每月需存 \(Money.format(max(0, goal.targetCents - progress) / months))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if goal.accountID != nil {
                    Label("跟随账户余额", systemImage: "link").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(goal.isArchived ? 0.5 : 1)
    }
}

private struct GoalEditor: View {
    let goal: SavingsGoal?
    let nextOrder: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.order) private var accounts: [Account]

    @State private var name: String
    @State private var symbol: String
    @State private var colorHex: String
    @State private var target: Int
    @State private var saved: Int
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var accountID: UUID?

    init(goal: SavingsGoal?, nextOrder: Int) {
        self.goal = goal
        self.nextOrder = nextOrder
        _name = State(initialValue: goal?.name ?? "")
        _symbol = State(initialValue: goal?.symbol ?? "airplane")
        _colorHex = State(initialValue: goal?.colorHex ?? "#FF9F0A")
        _target = State(initialValue: goal?.targetCents ?? 0)
        _saved = State(initialValue: goal?.savedCents ?? 0)
        _hasDeadline = State(initialValue: goal?.deadline != nil)
        _deadline = State(initialValue: goal?.deadline ?? Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now)
        _accountID = State(initialValue: goal?.accountID)
    }

    var body: some View {
        NavigationStack {
            Form {
                HStack(spacing: 14) {
                    CategoryIcon(symbol: symbol, color: Color(hex: colorHex), size: 52, filled: true)
                    TextField("目标名称，如「日本旅行」", text: $name).font(.title3.weight(.semibold))
                }
                Section {
                    CentsField(title: "目标金额", cents: $target)
                    Picker("关联账户", selection: $accountID) {
                        Text("不关联（手动存入）").tag(UUID?.none)
                        ForEach(accounts) { Text($0.name).tag(Optional($0.uuid)) }
                    }
                    if accountID == nil {
                        CentsField(title: "已存金额", cents: $saved)
                    }
                    Toggle("截止日期", isOn: $hasDeadline.animation())
                    if hasDeadline {
                        DatePicker("截止于", selection: $deadline, displayedComponents: .date)
                    }
                }
                Section("颜色") { ColorSwatchPicker(hex: $colorHex) }
                Section("图标") { SymbolGridPicker(selection: $symbol, color: Color(hex: colorHex)).padding(.vertical, 6) }
            }
            .navigationTitle(goal == nil ? "新建目标" : "编辑目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark", role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", systemImage: "checkmark", role: .confirm) {
                        let target = goal ?? SavingsGoal(name: "", targetCents: 0)
                        if goal == nil {
                            target.order = nextOrder
                            context.insert(target)
                        }
                        target.name = name.trimmingCharacters(in: .whitespaces)
                        target.symbol = symbol
                        target.colorHex = colorHex
                        target.targetCents = self.target
                        target.savedCents = saved
                        target.deadline = hasDeadline ? deadline : nil
                        target.accountID = accountID
                        try? context.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || target <= 0)
                }
            }
        }
    }
}

// MARK: - Debts

struct DebtsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Debt.date, order: .reverse) private var debts: [Debt]
    @State private var editing: Debt?
    @State private var creating = false
    @State private var repaying: Debt?
    @State private var repayCents = 0
    @State private var showSettled = false

    var body: some View {
        let open = debts.filter { !$0.isSettled }
        let receivable = open.filter(\.isLent).reduce(0) { $0 + AppSettings.shared.convertToBase($1.remainingCents, from: $1.currencyCode) }
        let payable = open.filter { !$0.isLent }.reduce(0) { $0 + AppSettings.shared.convertToBase($1.remainingCents, from: $1.currencyCode) }
        let visible = debts.filter { showSettled || !$0.isSettled }

        List {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("别人欠我").font(.caption).foregroundStyle(.secondary)
                    Text(Money.format(receivable)).font(.title3.bold().monospacedDigit()).foregroundStyle(Color.income)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text("我欠别人").font(.caption).foregroundStyle(.secondary)
                    Text(Money.format(payable)).font(.title3.bold().monospacedDigit()).foregroundStyle(Color.expense)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .glassCard(cornerRadius: 28)
            .plainListRow(top: 8, bottom: 8)

            if debts.isEmpty {
                ContentUnavailableView("没有借贷记录", systemImage: "person.2",
                                       description: Text("记下借给朋友或向别人借的钱，到期提醒不再尴尬。"))
                    .plainListRow()
            }

            ForEach(visible) { debt in
                DebtRow(debt: debt)
                    .contentShape(.rect)
                    .onTapGesture { editing = debt }
                    .swipeActions(edge: .leading) {
                        if !debt.isSettled {
                            Button {
                                repayCents = debt.remainingCents
                                repaying = debt
                            } label: {
                                Label(debt.isLent ? "收款" : "还款", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            context.delete(debt)
                            try? context.save()
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(tint: .teal) }
        .navigationTitle("借贷")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("显示已结清", isOn: $showSettled)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("新建", systemImage: "plus") { creating = true }
                    .buttonStyle(.glassProminent)
            }
        }
        .sheet(isPresented: $creating) { DebtEditor(debt: nil) }
        .sheet(item: $editing) { DebtEditor(debt: $0) }
        .sheet(item: $repaying) { debt in
            NavigationStack {
                Form {
                    CentsField(title: debt.isLent ? "本次收回" : "本次归还", cents: $repayCents, code: debt.currencyCode)
                    LabeledContent("剩余", value: Money.format(debt.remainingCents, code: debt.currencyCode))
                }
                .navigationTitle(debt.person)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确定", systemImage: "checkmark", role: .confirm) {
                            debt.repaidCents = min(debt.amountCents, debt.repaidCents + repayCents)
                            if debt.remainingCents == 0 { debt.isSettled = true }
                            try? context.save()
                            Haptics.success()
                            repaying = nil
                        }
                        .disabled(repayCents <= 0)
                    }
                }
            }
            .presentationDetents([.height(260)])
        }
    }
}

private struct DebtRow: View {
    let debt: Debt

    var body: some View {
        HStack(spacing: 12) {
            Text(String(debt.person.prefix(1)))
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background((debt.isLent ? Color.income : Color.expense).gradient, in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(debt.person).font(.body.weight(.medium))
                    Text(debt.isLent ? "借出" : "借入")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background((debt.isLent ? Color.income : Color.expense).opacity(0.15), in: .capsule)
                }
                Group {
                    if debt.isSettled {
                        Text("已结清")
                    } else if let due = debt.dueDate {
                        let overdue = due < .now
                        Text(overdue ? "已逾期 · \(due.zh("MMMd"))" : "\(due.zh("MMMd")) 到期")
                            .foregroundStyle(overdue ? Color.expense : Color.secondary)
                    } else {
                        Text(debt.date.zh("yMMMd"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(debt.remainingCents, code: debt.currencyCode))
                    .font(.body.weight(.semibold).monospacedDigit())
                if debt.repaidCents > 0 && !debt.isSettled {
                    Text("共 \(Money.format(debt.amountCents, code: debt.currencyCode))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .opacity(debt.isSettled ? 0.5 : 1)
    }
}

private struct DebtEditor: View {
    let debt: Debt?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var lent: Bool
    @State private var person: String
    @State private var amount: Int
    @State private var repaid: Int
    @State private var date: Date
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var note: String
    @State private var settled: Bool

    init(debt: Debt?) {
        self.debt = debt
        _lent = State(initialValue: debt?.isLent ?? true)
        _person = State(initialValue: debt?.person ?? "")
        _amount = State(initialValue: debt?.amountCents ?? 0)
        _repaid = State(initialValue: debt?.repaidCents ?? 0)
        _date = State(initialValue: debt?.date ?? .now)
        _hasDue = State(initialValue: debt?.dueDate != nil)
        _due = State(initialValue: debt?.dueDate ?? Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now)
        _note = State(initialValue: debt?.note ?? "")
        _settled = State(initialValue: debt?.isSettled ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("类型", selection: $lent) {
                    Text("我借出").tag(true)
                    Text("我借入").tag(false)
                }
                .pickerStyle(.segmented)
                Section {
                    TextField("对方", text: $person)
                    CentsField(title: "金额", cents: $amount)
                    if debt != nil { CentsField(title: "已还", cents: $repaid) }
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    Toggle("约定还款日", isOn: $hasDue.animation())
                    if hasDue { DatePicker("还款日", selection: $due, displayedComponents: .date) }
                    TextField("备注", text: $note)
                    if debt != nil { Toggle("已结清", isOn: $settled) }
                }
            }
            .navigationTitle(debt == nil ? "新建借贷" : "编辑借贷")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark", role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", systemImage: "checkmark", role: .confirm) {
                        let target = debt ?? Debt(lent: lent, person: "", amountCents: 0)
                        if debt == nil { context.insert(target) }
                        target.directionRaw = lent ? 0 : 1
                        target.person = person.trimmingCharacters(in: .whitespaces)
                        target.amountCents = amount
                        target.repaidCents = min(repaid, amount)
                        target.date = date
                        target.dueDate = hasDue ? due : nil
                        target.note = note
                        target.isSettled = settled || target.remainingCents == 0 && debt != nil
                        try? context.save()
                        dismiss()
                    }
                    .disabled(person.trimmingCharacters(in: .whitespaces).isEmpty || amount <= 0)
                }
            }
        }
    }
}

// MARK: - Reimbursements

struct ReimbursementsView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Record> { $0.reimbursementRaw > 0 }, sort: \Record.date, order: .reverse)
    private var records: [Record]
    @State private var showDone = false

    var body: some View {
        let pending = records.filter { $0.reimbursement == .pending }
        let done = records.filter { $0.reimbursement == .done }
        let pendingTotal = pending.reduce(0) { $0 + $1.baseAmountCents }

        List {
            VStack(alignment: .leading, spacing: 6) {
                Text("待报销").font(.subheadline).foregroundStyle(.secondary)
                Text(Money.format(pendingTotal)).font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                Text("\(pending.count) 笔 · 记账时打开「报销」即可加入").font(.caption).foregroundStyle(.secondary)
            }
            .glassCard(cornerRadius: 28, tint: Color.cyan.opacity(0.08))
            .plainListRow(top: 8, bottom: 8)

            Section("待报销") {
                if pending.isEmpty { Text("没有待报销的账单").foregroundStyle(.secondary) }
                ForEach(pending) { record in
                    NavigationLink(value: record) { RecordRow(record: record, showDate: true) }
                        .swipeActions(edge: .leading) {
                            Button {
                                record.reimbursement = .done
                                try? context.save()
                                Haptics.success()
                            } label: {
                                Label("已报销", systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                }
            }
            if showDone {
                Section("已报销") {
                    ForEach(done) { record in
                        NavigationLink(value: record) { RecordRow(record: record, showDate: true) }
                            .swipeActions(edge: .leading) {
                                Button {
                                    record.reimbursement = .pending
                                    try? context.save()
                                } label: {
                                    Label("撤回", systemImage: "arrow.uturn.backward")
                                }
                            }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(tint: .cyan) }
        .navigationTitle("报销")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $showDone) { Label("显示已报销", systemImage: "checkmark.circle") }
                    .toggleStyle(.button)
            }
            if !pending.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button("全部标记为已报销") {
                        for record in pending { record.reimbursement = .done }
                        try? context.save()
                        Haptics.success()
                    }
                }
            }
        }
        .navigationDestination(for: Record.self) { RecordDetailView(record: $0) }
    }
}
