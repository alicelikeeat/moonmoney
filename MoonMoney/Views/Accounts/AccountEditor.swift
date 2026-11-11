import SwiftData
import SwiftUI

struct AccountEditor: View {
    let account: Account?
    /// Off when presented from the account's own detail page, which would outlive the deleted model.
    var allowsDelete = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query private var allAccounts: [Account]

    @State private var name: String
    @State private var type: AccountType
    @State private var symbol: String
    @State private var iconImage: Data?
    @State private var colorHex: String
    @State private var currency: String
    @State private var balanceCents: Int
    @State private var creditLimitCents: Int
    @State private var billingDay: Int
    @State private var dueDay: Int
    @State private var includeInNetWorth: Bool
    @State private var note: String
    @State private var isDefault: Bool
    @State private var confirmDelete = false

    init(account: Account?, allowsDelete: Bool = true) {
        self.account = account
        self.allowsDelete = allowsDelete
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.type ?? .debit)
        _symbol = State(initialValue: account?.symbol ?? AccountType.debit.defaultSymbol)
        _iconImage = State(initialValue: account?.iconImage)
        _colorHex = State(initialValue: account?.colorHex ?? "#0A84FF")
        _currency = State(initialValue: account?.currencyCode ?? AppSettings.shared.baseCurrency)
        // Editing shows the current balance; saving back-solves the initial balance.
        _balanceCents = State(initialValue: account?.balanceCents ?? 0)
        _creditLimitCents = State(initialValue: account?.creditLimitCents ?? 0)
        _billingDay = State(initialValue: account?.billingDay ?? 0)
        _dueDay = State(initialValue: account?.dueDay ?? 0)
        _includeInNetWorth = State(initialValue: account?.includeInNetWorth ?? true)
        _note = State(initialValue: account?.note ?? "")
        _isDefault = State(initialValue: account != nil && account?.uuid == AppSettings.shared.defaultAccountID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        HStack(spacing: 14) {
                            CategoryIcon(symbol: symbol, color: Color(hex: colorHex), size: 52, filled: true, image: iconImage)
                            TextField("账户名称", text: $name)
                                .font(.title3.weight(.semibold))
                        }
                        Picker("类型", selection: $type) {
                            ForEach(AccountType.allCases) { type in
                                Label(type.title, systemImage: type.defaultSymbol).tag(type)
                            }
                        }
                        .onChange(of: type) { oldValue, newValue in
                            if symbol == oldValue.defaultSymbol { symbol = newValue.defaultSymbol }
                        }
                        Picker("币种", selection: $currency) {
                            ForEach(currencyOptions, id: \.self) { code in
                                Text("\(code) · \(Currencies.name(code))").tag(code)
                            }
                        }
                    }

                    Section {
                        CentsField(title: type == .credit ? "当前余额（欠款为负）" : "当前余额", cents: $balanceCents, code: currency)
                        if type == .credit {
                            CentsField(title: "信用额度", cents: $creditLimitCents, code: currency)
                            Picker("账单日", selection: $billingDay) {
                                Text("不设置").tag(0)
                                ForEach(1...28, id: \.self) { Text("每月\($0)日").tag($0) }
                            }
                            Picker("还款日", selection: $dueDay) {
                                Text("不设置").tag(0)
                                ForEach(1...28, id: \.self) { Text("每月\($0)日").tag($0) }
                            }
                        }
                        Toggle("计入净资产", isOn: $includeInNetWorth)
                        Toggle("设为默认记账账户", isOn: $isDefault)
                        TextField("备注（如卡号后四位）", text: $note)
                    }

                    Section("颜色") {
                        ColorSwatchPicker(hex: $colorHex)
                    }

                    Section("图标") {
                        SymbolGridPicker(selection: $symbol, color: Color(hex: colorHex), image: $iconImage)
                            .padding(.vertical, 6)
                    }

                    if account != nil && allowsDelete {
                        Section {
                            Button("删除账户", role: .destructive) { confirmDelete = true }
                        } footer: {
                            Text("删除后，相关账单会保留但不再关联此账户。若只是不再使用，建议在列表中左滑归档。")
                        }
                    }
                }
                .listRowBackground(GlassRowBackground())
            }
            .pageBackground()
            .navigationTitle(account == nil ? "新建账户" : "编辑账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark", role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", systemImage: "checkmark", role: .confirm, action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("删除「\(name)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    let target = account
                    dismiss()
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        if let target {
                            if settings.defaultAccountID == target.uuid { settings.defaultAccountID = nil }
                            context.delete(target)
                            try? context.save()
                        }
                    }
                }
            }
        }
    }

    private var currencyOptions: [String] {
        var codes = Currencies.common
        if !codes.contains(currency) { codes.insert(currency, at: 0) }
        return codes
    }

    private func save() {
        let target = account ?? Account(name: "", type: type, order: allAccounts.count)
        if account == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.type = type
        target.symbol = symbol
        target.iconImage = iconImage
        target.colorHex = colorHex
        target.currencyCode = currency
        target.creditLimitCents = creditLimitCents
        target.billingDay = billingDay
        target.dueDay = dueDay
        target.includeInNetWorth = includeInNetWorth
        target.note = note
        // Back-solve the opening balance so the displayed balance matches what the user typed.
        let movement = target.balanceCents - target.initialBalanceCents
        target.initialBalanceCents = balanceCents - movement
        if isDefault {
            settings.defaultAccountID = target.uuid
        } else if settings.defaultAccountID == target.uuid {
            settings.defaultAccountID = nil
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
