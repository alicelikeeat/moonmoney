import SwiftData
import SwiftUI

// MARK: - Ledgers

struct LedgerManagerView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Ledger.order) private var ledgers: [Ledger]
    @State private var editing: Ledger?
    @State private var creating = false
    @State private var pendingDelete: Ledger?

    var body: some View {
        List {
            Group {
                Section {
                    ForEach(ledgers) { ledger in
                        Button {
                            settings.currentLedgerID = ledger.uuid
                            Haptics.tap()
                        } label: {
                            HStack(spacing: 12) {
                                CategoryIcon(symbol: ledger.symbol, color: ledger.color, size: 40, filled: true, image: ledger.iconImage)
                                Text(ledger.name).foregroundStyle(.primary)
                                Spacer()
                                if ledger.uuid == settings.currentLedgerID {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                }
                            }
                        }
                        .swipeActions {
                            if ledgers.count > 1 {
                                Button(role: .destructive) {
                                    pendingDelete = ledger
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            Button {
                                editing = ledger
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                    .onMove { indices, destination in
                        var items = ledgers
                        items.move(fromOffsets: indices, toOffset: destination)
                        for (index, item) in items.enumerated() { item.order = index }
                        try? context.save()
                    }
                } footer: {
                    Text("每个账本的账单、预算相互独立；账户与分类在所有账本间共享。")
                }
            }
            .listRowBackground(GlassRowBackground())
        }
        .pageBackground()
        .navigationTitle("账本")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button("新建账本", systemImage: "plus") { creating = true }
            }
        }
        .sheet(isPresented: $creating) { LedgerEditor(ledger: nil, nextOrder: ledgers.count) }
        .sheet(item: $editing) { LedgerEditor(ledger: $0, nextOrder: ledgers.count) }
        .confirmationDialog(
            "删除账本「\(pendingDelete?.name ?? "")」及其全部账单？",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let ledger = pendingDelete { delete(ledger) }
            }
        } message: {
            Text("此操作无法撤销。")
        }
    }

    private func delete(_ ledger: Ledger) {
        let id: UUID? = ledger.uuid
        try? context.delete(model: Record.self, where: #Predicate<Record> { $0.ledgerID == id })
        try? context.delete(model: Budget.self, where: #Predicate<Budget> { $0.ledgerID == id })
        context.delete(ledger)
        if settings.currentLedgerID == ledger.uuid {
            settings.currentLedgerID = ledgers.first { $0.uuid != ledger.uuid }?.uuid
        }
        try? context.save()
        pendingDelete = nil
    }
}

struct LedgerEditor: View {
    let ledger: Ledger?
    let nextOrder: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name: String
    @State private var symbol: String
    @State private var iconImage: Data?
    @State private var colorHex: String

    init(ledger: Ledger?, nextOrder: Int) {
        self.ledger = ledger
        self.nextOrder = nextOrder
        _name = State(initialValue: ledger?.name ?? "")
        _symbol = State(initialValue: ledger?.symbol ?? "book.closed.fill")
        _iconImage = State(initialValue: ledger?.iconImage)
        _colorHex = State(initialValue: ledger?.colorHex ?? "#5E5CE6")
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    HStack(spacing: 14) {
                        CategoryIcon(symbol: symbol, color: Color(hex: colorHex), size: 52, filled: true, image: iconImage)
                        TextField("账本名称，如「旅行」「装修」", text: $name)
                            .font(Font.skin(.title3).weight(.semibold))
                    }
                    Section { ColorSwatchPicker(hex: $colorHex) } header: {
 SectionTitle("颜色")
 }
                    Section {
                        SymbolGridPicker(selection: $symbol, color: Color(hex: colorHex), image: $iconImage).padding(.vertical, 6)
                    } header: {
 SectionTitle("图标")
 }
                }
                .listRowBackground(GlassRowBackground())
            }
            .pageBackground()
            .navigationTitle(ledger == nil ? "新建账本" : "编辑账本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark", role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", systemImage: "checkmark", role: .confirm) {
                        let target = ledger ?? Ledger(name: "", order: nextOrder)
                        if ledger == nil { context.insert(target) }
                        target.name = name.trimmingCharacters(in: .whitespaces)
                        target.symbol = symbol
                        target.iconImage = iconImage
                        target.colorHex = colorHex
                        try? context.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Categories

struct CategoryManagerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BillCategory.order) private var categories: [BillCategory]
    @State private var kind: RecordKind
    @State private var editing: BillCategory?
    @State private var creating = false

    init(initialKind: RecordKind) {
        _kind = State(initialValue: initialKind)
    }

    var body: some View {
        let active = categories.filter { $0.kind == kind && !$0.isArchived }
        let archived = categories.filter { $0.kind == kind && $0.isArchived }

        List {
            Group {
                Section {
                    ForEach(active) { category in
                        row(category)
                    }
                    .onMove { indices, destination in
                        var items = active
                        items.move(fromOffsets: indices, toOffset: destination)
                        for (index, item) in items.enumerated() { item.order = index }
                        try? context.save()
                    }
                } footer: {
                    Text("左滑可归档：归档后不再出现在记账面板，但历史账单保留。")
                }
                if !archived.isEmpty {
                    Section {
                        ForEach(archived) { category in
                            row(category).opacity(0.6)
                        }
                    } header: {
 SectionTitle("已归档")
 }
                }
            }
            .listRowBackground(GlassRowBackground())
        }
        .pageBackground()
        .navigationTitle("分类")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("类型", selection: $kind) {
                    Text("支出").tag(RecordKind.expense)
                    Text("收入").tag(RecordKind.income)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button("新建分类", systemImage: "plus") { creating = true }
            }
        }
        .sheet(isPresented: $creating) {
            CategoryEditor(category: nil, kind: kind, nextOrder: active.count)
        }
        .sheet(item: $editing) { category in
            CategoryEditor(category: category, kind: category.kind, nextOrder: active.count)
        }
    }

    private func row(_ category: BillCategory) -> some View {
        Button {
            editing = category
        } label: {
            HStack(spacing: 12) {
                CategoryIcon(symbol: category.symbol, color: category.color, size: 38, image: category.iconImage)
                Text(category.name).foregroundStyle(.primary)
                Spacer()
                Text("\(category.records?.count ?? 0) 笔")
                    .font(Font.skin(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions {
            Button {
                category.isArchived.toggle()
                try? context.save()
            } label: {
                Label(category.isArchived ? "恢复" : "归档", systemImage: "archivebox")
            }
            .tint(.gray)
        }
    }
}

struct CategoryEditor: View {
    let category: BillCategory?
    let kind: RecordKind
    let nextOrder: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name: String
    @State private var symbol: String
    @State private var iconImage: Data?
    @State private var colorHex: String
    @State private var confirmDelete = false

    init(category: BillCategory?, kind: RecordKind, nextOrder: Int) {
        self.category = category
        self.kind = kind
        self.nextOrder = nextOrder
        _name = State(initialValue: category?.name ?? "")
        _symbol = State(initialValue: category?.symbol ?? "tag.fill")
        _iconImage = State(initialValue: category?.iconImage)
        _colorHex = State(initialValue: category?.colorHex ?? (Palette.swatches.randomElement() ?? "#FF9F0A"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    HStack(spacing: 14) {
                        CategoryIcon(symbol: symbol, color: Color(hex: colorHex), size: 52, filled: true, image: iconImage)
                        TextField("分类名称", text: $name)
                            .font(Font.skin(.title3).weight(.semibold))
                    }
                    Section { ColorSwatchPicker(hex: $colorHex) } header: {
 SectionTitle("颜色")
 }
                    Section {
                        SymbolGridPicker(selection: $symbol, color: Color(hex: colorHex), image: $iconImage).padding(.vertical, 6)
                    } header: {
 SectionTitle("图标")
 }
                    if category != nil {
                        Section {
                            Button("删除分类", role: .destructive) { confirmDelete = true }
                        } footer: {
                            Text("删除后相关账单会变为「未分类」。")
                        }
                    }
                }
                .listRowBackground(GlassRowBackground())
            }
            .pageBackground()
            .navigationTitle(category == nil ? "新建\(kind.title)分类" : "编辑分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark", role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", systemImage: "checkmark", role: .confirm) {
                        let target = category ?? BillCategory(name: "", symbol: symbol, colorHex: colorHex, kind: kind, order: nextOrder)
                        if category == nil { context.insert(target) }
                        target.name = name.trimmingCharacters(in: .whitespaces)
                        target.symbol = symbol
                        target.iconImage = iconImage
                        target.colorHex = colorHex
                        try? context.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("删除「\(name)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    let target = category
                    dismiss()
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        if let target {
                            context.delete(target)
                            try? context.save()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Tags

struct TagManagerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecordTag.name) private var tags: [RecordTag]
    @State private var newName = ""
    @State private var renaming: RecordTag?
    @State private var renameText = ""

    var body: some View {
        List {
            Group {
                Section {
                    HStack {
                        TextField("新建标签", text: $newName)
                            .onSubmit(add)
                        Button("添加", action: add)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    ForEach(tags) { tag in
                        HStack {
                            Circle().fill(tag.color).frame(width: 10, height: 10)
                            Text("#\(tag.name)")
                            Spacer()
                            Text("\(tag.records?.count ?? 0) 笔").font(Font.skin(.caption)).foregroundStyle(.secondary)
                        }
                        .contentShape(.rect)
                        .onTapGesture {
                            renameText = tag.name
                            renaming = tag
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(tags[index]) }
                        try? context.save()
                    }
                } footer: {
                    Text("标签可跨分类标记账单，例如「报销」「旅行」，并可在搜索中筛选。")
                }
            }
            .listRowBackground(GlassRowBackground())
        }
        .pageBackground()
        .navigationTitle("标签")
        .alert("重命名标签", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { renaming?.name = name }
                try? context.save()
            }
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !tags.contains(where: { $0.name == name }) else { return }
        context.insert(RecordTag(name: name, colorHex: Palette.swatches.randomElement() ?? "#64D2FF"))
        try? context.save()
        newName = ""
    }
}

// MARK: - Exchange rates

struct ExchangeRatesView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        List {
            Group {
                Section {
                    ForEach(Currencies.common.filter { $0 != settings.baseCurrency }, id: \.self) { code in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(code).font(Font.skin(.headline))
                                Text(Currencies.name(code)).font(Font.skin(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("1 \(code) =")
                                .foregroundStyle(.secondary)
                            TextField("汇率", value: Binding(
                                get: { settings.rates[code] ?? 0 },
                                set: { settings.rates[code] = $0 }
                            ), format: .number.precision(.fractionLength(0...6)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            Text(settings.baseCurrency).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("外币账户的账单会按此汇率折算为本位币参与统计和预算。")
                }
            }
            .listRowBackground(GlassRowBackground())
        }
        .pageBackground()
        .navigationTitle("汇率")
    }
}
