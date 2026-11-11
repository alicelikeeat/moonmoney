import SwiftData
import SwiftUI

struct BudgetView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        BudgetContent(interval: Periods.month(containing: .now), ledgerID: settings.currentLedgerID)
            .id(settings.currentLedgerID)
            .navigationTitle("预算")
    }
}

private struct BudgetContent: View {
    @Environment(\.modelContext) private var context
    @Query private var records: [Record]
    @Query private var budgets: [Budget]
    @Query(filter: #Predicate<BillCategory> { $0.kindRaw == 0 && !$0.isArchived }, sort: \BillCategory.order)
    private var expenseCategories: [BillCategory]

    let interval: DateInterval
    let ledgerID: UUID?

    @State private var editingTotal = false
    @State private var totalText = ""
    @State private var addingCategory = false
    @State private var editingBudget: Budget?

    init(interval: DateInterval, ledgerID: UUID?) {
        self.interval = interval
        self.ledgerID = ledgerID
        let start = interval.start
        let end = interval.end
        _records = Query(filter: #Predicate<Record> {
            $0.date >= start && $0.date < end && $0.ledgerID == ledgerID && $0.kindRaw == 0
        })
        _budgets = Query(filter: #Predicate<Budget> { $0.ledgerID == ledgerID }, sort: \Budget.createdAt)
    }

    var body: some View {
        let counted = Stats.counted(records)
        let spent = counted.reduce(0) { $0 + $1.baseAmountCents }
        let total = budgets.first { $0.category == nil }
        let categoryBudgets = budgets.filter { $0.category != nil }

        List {
            Group {
                totalCard(total: total, spent: spent)
                    .plainListRow(top: 8, bottom: 8)

                Section {
                    ForEach(categoryBudgets) { budget in
                        if let category = budget.category {
                            let used = counted.filter { $0.category?.uuid == category.uuid }.reduce(0) { $0 + $1.baseAmountCents }
                            CategoryBudgetRow(category: category, budget: budget.amountCents, used: used)
                                .contentShape(.rect)
                                .onTapGesture { editingBudget = budget }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        context.delete(budget)
                                        try? context.save()
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    Button {
                        addingCategory = true
                    } label: {
                        Label("添加分类预算", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("分类预算")
                } footer: {
                    Text("预算按「每月起始日」（当前为每月 \(AppSettings.shared.monthStartDay) 日）计算，所有币种折算为本位币。")
                }
            }
            .listRowBackground(GlassRowBackground())
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(tint: .green) }
        .alert("月度总预算", isPresented: $editingTotal) {
            TextField("金额", text: $totalText)
                .keyboardType(.decimalPad)
            Button("取消", role: .cancel) {}
            if total != nil {
                Button("删除预算", role: .destructive) {
                    if let total { context.delete(total); try? context.save() }
                }
            }
            Button("保存") { saveTotal(existing: total) }
        }
        .sheet(isPresented: $addingCategory) {
            CategoryBudgetEditor(budget: nil, categories: expenseCategories.filter { category in
                !categoryBudgets.contains { $0.category?.uuid == category.uuid }
            }, ledgerID: ledgerID)
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingBudget) { budget in
            CategoryBudgetEditor(budget: budget, categories: [], ledgerID: ledgerID)
                .presentationDetents([.medium])
        }
    }

    private func totalCard(total: Budget?, spent: Int) -> some View {
        let limit = total?.amountCents ?? 0
        let ratio = limit > 0 ? Double(spent) / Double(limit) : 0
        let remaining = limit - spent
        let days = Periods.remainingDays(in: interval)
        let tint: Color = ratio >= 1 ? .expense : (ratio > 0.8 ? .orange : .income)

        return VStack(spacing: 18) {
            HStack(spacing: 20) {
                ZStack {
                    RingGauge(value: ratio, tint: tint, lineWidth: 14)
                    VStack(spacing: 0) {
                        Text(limit > 0 ? ratio.formatted(.percent.precision(.fractionLength(0))) : "—")
                            .font(.title2.bold().monospacedDigit())
                        Text("已用").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 10) {
                    row("本月预算", limit > 0 ? Money.format(limit) : "未设置")
                    row("已支出", Money.format(spent))
                    row(remaining >= 0 ? "剩余" : "超支", Money.format(abs(remaining)),
                        color: remaining >= 0 ? .primary : .expense)
                    if limit > 0 && remaining > 0 && days > 0 {
                        row("日均可用", Money.format(remaining / days), color: .income)
                    }
                }
            }
            Button {
                totalText = limit > 0 ? Money.plain(limit).replacingOccurrences(of: ",", with: "") : ""
                editingTotal = true
            } label: {
                Label(limit > 0 ? "修改总预算" : "设置总预算", systemImage: "target")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.inCard(prominent: true))
        }
        .glassCard(cornerRadius: 32, padding: 20)
    }

    private func row(_ title: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(color)
        }
    }

    private func saveTotal(existing: Budget?) {
        guard let value = Decimal(string: totalText, locale: Locale(identifier: "en_US_POSIX")) else { return }
        let cents = Money.cents(value)
        if let existing {
            existing.amountCents = cents
        } else {
            context.insert(Budget(amountCents: cents, ledgerID: ledgerID))
        }
        try? context.save()
        Haptics.success()
    }
}

private struct CategoryBudgetRow: View {
    let category: BillCategory
    let budget: Int
    let used: Int

    var body: some View {
        let ratio = Double(used) / Double(max(budget, 1))
        let tint: Color = ratio >= 1 ? .expense : (ratio > 0.8 ? .orange : category.color)
        HStack(spacing: 12) {
            CategoryIcon(symbol: category.symbol, color: category.color, size: 38)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(category.name).font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(Money.format(used)) / \(Money.format(budget))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ratio >= 1 ? Color.expense : Color.secondary)
                }
                ProgressCapsule(value: ratio, tint: tint, height: 6)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CategoryBudgetEditor: View {
    let budget: Budget?
    let categories: [BillCategory]
    let ledgerID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var category: BillCategory?
    @State private var cents: Int

    init(budget: Budget?, categories: [BillCategory], ledgerID: UUID?) {
        self.budget = budget
        self.categories = categories
        self.ledgerID = ledgerID
        _category = State(initialValue: budget?.category ?? categories.first)
        _cents = State(initialValue: budget?.amountCents ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                if budget == nil {
                    Picker("分类", selection: $category) {
                        ForEach(categories) { item in
                            Label(item.name, systemImage: item.symbol).tag(Optional(item))
                        }
                    }
                } else if let category {
                    Label(category.name, systemImage: category.symbol)
                }
                CentsField(title: "每月预算", cents: $cents)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(budget == nil ? "添加分类预算" : "编辑分类预算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark", role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", systemImage: "checkmark", role: .confirm) {
                        if let budget {
                            budget.amountCents = cents
                        } else if let category {
                            context.insert(Budget(amountCents: cents, ledgerID: ledgerID, category: category))
                        }
                        try? context.save()
                        dismiss()
                    }
                    .disabled(cents <= 0 || category == nil)
                }
            }
        }
    }
}
