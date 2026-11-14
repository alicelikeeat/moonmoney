import SwiftData
import SwiftUI

struct RecurringListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecurringRule.nextDate) private var rules: [RecurringRule]
    @Query private var categories: [BillCategory]
    @State private var editing: RecurringRule?
    @State private var creating = false

    var body: some View {
        let active = rules.filter(\.isActive)
        let monthly = active.filter { $0.kind == .expense }.reduce(0.0) { sum, rule in
            sum + monthlyEquivalent(rule)
        }

        List {
            Group {
                VStack(alignment: .leading, spacing: 6) {
                    Text("订阅与固定支出（每月约）").font(Font.skin(.subheadline)).foregroundStyle(.secondary)
                    Text(Money.format(Int(monthly)))
                        .font(.money(32))
                    Text("\(active.count) 个生效中的规则，到期时自动入账").font(Font.skin(.caption)).foregroundStyle(.secondary)
                }
                .glassCard(cornerRadius: 28, tint: Color.purple.opacity(0.1))
                .plainListRow(top: 8, bottom: 8)

                if rules.isEmpty {
                    ContentUnavailableView("还没有周期记账", systemImage: "repeat",
                                           description: Text("房租、工资、会员订阅……设置一次，按时自动记账。"))
                        .plainListRow()
                }

                Section {
                    ForEach(rules) { rule in
                        Button {
                            editing = rule
                        } label: {
                            RecurringRow(rule: rule, category: categories.first { $0.uuid == rule.categoryID })
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                context.delete(rule)
                                try? context.save()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                rule.isActive.toggle()
                                if rule.isActive { RecurringEngine.run(in: context) }
                                try? context.save()
                            } label: {
                                Label(rule.isActive ? "暂停" : "恢复", systemImage: rule.isActive ? "pause" : "play")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
            .listRowBackground(GlassRowBackground())
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(tint: .purple) }
        .navigationTitle("周期记账")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("新建", systemImage: "plus") { creating = true }
                    .buttonStyle(.glassProminent)
            }
        }
        .sheet(isPresented: $creating) { RecurringEditor(rule: nil) }
        .sheet(item: $editing) { RecurringEditor(rule: $0) }
    }

    private func monthlyEquivalent(_ rule: RecurringRule) -> Double {
        let amount = Double(rule.amountCents)
        let interval = Double(max(1, rule.interval))
        switch rule.frequency {
        case .daily: return amount * 30 / interval
        case .weekly: return amount * 4.345 / interval
        case .monthly: return amount / interval
        case .yearly: return amount / 12 / interval
        }
    }
}

private struct RecurringRow: View {
    let rule: RecurringRule
    let category: BillCategory?

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(symbol: rule.kind == .transfer ? "arrow.left.arrow.right" : (category?.symbol ?? "repeat"),
                         color: rule.kind == .transfer ? .transfer : (category?.color ?? .purple), size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name.isEmpty ? (category?.name ?? "周期记账") : rule.name)
                    .font(Font.skin(.body).weight(.medium))
                Text(rule.isActive ? "\(rule.scheduleDescription) · 下次 \(rule.nextDate.zh("MMMd"))" : "已暂停")
                    .font(Font.skin(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AmountText(cents: rule.amountCents, kind: rule.kind)
        }
        .contentShape(.rect)
        .opacity(rule.isActive ? 1 : 0.5)
    }
}

struct RecurringEditor: View {
    let rule: RecurringRule?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<BillCategory> { !$0.isArchived }, sort: \BillCategory.order)
    private var categories: [BillCategory]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.order)
    private var accounts: [Account]

    @State private var name: String
    @State private var kind: RecordKind
    @State private var cents: Int
    @State private var frequency: RecurrenceFrequency
    @State private var interval: Int
    @State private var nextDate: Date
    @State private var hasEnd: Bool
    @State private var endDate: Date
    @State private var categoryID: UUID?
    @State private var accountID: UUID?
    @State private var toAccountID: UUID?
    @State private var note: String

    init(rule: RecurringRule?) {
        self.rule = rule
        _name = State(initialValue: rule?.name ?? "")
        _kind = State(initialValue: rule?.kind ?? .expense)
        _cents = State(initialValue: rule?.amountCents ?? 0)
        _frequency = State(initialValue: rule?.frequency ?? .monthly)
        _interval = State(initialValue: rule?.interval ?? 1)
        _nextDate = State(initialValue: rule?.nextDate ?? .now)
        _hasEnd = State(initialValue: rule?.endDate != nil)
        _endDate = State(initialValue: rule?.endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now)
        _categoryID = State(initialValue: rule?.categoryID)
        _accountID = State(initialValue: rule?.accountID ?? AppSettings.shared.defaultAccountID)
        _toAccountID = State(initialValue: rule?.toAccountID)
        _note = State(initialValue: rule?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        Picker("类型", selection: $kind) {
                            ForEach(RecordKind.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        TextField("名称，如「房租」「Apple One」", text: $name)
                        CentsField(title: "金额", cents: $cents)
                    }

                    Section {
                        if kind == .transfer {
                            accountPicker("转出账户", selection: $accountID)
                            accountPicker("转入账户", selection: $toAccountID)
                        } else {
                            Picker("分类", selection: $categoryID) {
                                Text("未选择").tag(UUID?.none)
                                ForEach(categories.filter { $0.kind == kind }) { category in
                                    Label(category.name, systemImage: category.symbol).tag(Optional(category.uuid))
                                }
                            }
                            accountPicker("账户", selection: $accountID)
                        }
                        TextField("备注", text: $note)
                    }

                    Section {
                        Picker("频率", selection: $frequency) {
                            ForEach(RecurrenceFrequency.allCases) { Text($0.title).tag($0) }
                        }
                        Stepper("间隔：每 \(interval) \(unit)", value: $interval, in: 1...24)
                        DatePicker(rule == nil ? "首次记账" : "下次记账", selection: $nextDate, displayedComponents: [.date, .hourAndMinute])
                        Toggle("结束日期", isOn: $hasEnd.animation())
                        if hasEnd {
                            DatePicker("结束于", selection: $endDate, displayedComponents: .date)
                        }
                    } footer: {
                        Text("到期后打开 App 时自动生成账单；若首次日期在过去，会补齐之前的每一期。")
                    }
                }
                .listRowBackground(GlassRowBackground())
            }
            .pageBackground()
            .navigationTitle(rule == nil ? "新建周期记账" : "编辑周期记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark", role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", systemImage: "checkmark", role: .confirm, action: save)
                        .disabled(cents <= 0)
                }
            }
        }
    }

    private var unit: String {
        switch frequency {
        case .daily: "天"
        case .weekly: "周"
        case .monthly: "个月"
        case .yearly: "年"
        }
    }

    private func accountPicker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text("未选择").tag(UUID?.none)
            ForEach(accounts) { account in
                Label(account.name, systemImage: account.symbol).tag(Optional(account.uuid))
            }
        }
    }

    private func save() {
        let target = rule ?? RecurringRule(name: name, kind: kind, amountCents: cents, frequency: frequency, startDate: nextDate)
        if rule == nil {
            target.ledgerID = settings.currentLedgerID
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.kind = kind
        target.amountCents = cents
        target.frequency = frequency
        target.interval = interval
        target.nextDate = nextDate
        target.endDate = hasEnd ? endDate : nil
        target.categoryID = kind == .transfer ? nil : categoryID
        target.accountID = accountID
        target.toAccountID = kind == .transfer ? toAccountID : nil
        target.note = note
        target.isActive = true
        RecurringEngine.run(in: context)
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
