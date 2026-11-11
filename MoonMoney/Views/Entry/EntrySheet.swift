import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct EntrySheet: View {
    let request: EntryRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @Query(filter: #Predicate<BillCategory> { !$0.isArchived }, sort: \BillCategory.order)
    private var categories: [BillCategory]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.order)
    private var accounts: [Account]

    @State private var kind: RecordKind
    @State private var keypad: KeypadInput
    @State private var category: BillCategory?
    @State private var account: Account?
    @State private var toAccount: Account?
    @State private var date: Date
    @State private var note: String
    @State private var tags: [RecordTag]
    @State private var photo: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var excluded: Bool
    @State private var feeCents: Int
    @State private var toAmountCents: Int

    @State private var showTags = false
    @State private var showCategoryManager = false
    @State private var shakeAmount = 0
    @State private var savedToast: String?
    @State private var confirmDelete = false
    @FocusState private var noteFocused: Bool

    private var isEditing: Bool { request.record != nil }

    init(request: EntryRequest) {
        self.request = request
        let record = request.record
        _kind = State(initialValue: record?.kind ?? request.kind)
        _keypad = State(initialValue: KeypadInput(cents: record?.amountCents ?? 0))
        _category = State(initialValue: record?.category)
        _account = State(initialValue: record?.account ?? request.account)
        _toAccount = State(initialValue: record?.toAccount)
        _date = State(initialValue: record?.date ?? request.date ?? .now)
        _note = State(initialValue: record?.note ?? "")
        _tags = State(initialValue: record?.tags ?? [])
        _photo = State(initialValue: record?.photo)
        _excluded = State(initialValue: record?.excludedFromStats ?? false)
        _feeCents = State(initialValue: record?.feeCents ?? 0)
        _toAmountCents = State(initialValue: record?.toAmountCents ?? 0)
    }

    private var kindCategories: [BillCategory] {
        categories.filter { $0.kind == kind }
    }

    private var currencyCode: String {
        account?.currencyCode ?? settings.baseCurrency
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if kind == .transfer {
                        TransferPanel(
                            accounts: accounts,
                            from: $account,
                            to: $toAccount,
                            feeCents: $feeCents,
                            toAmountCents: $toAmountCents
                        )
                    } else {
                        CategoryGrid(
                            categories: kindCategories,
                            selection: $category,
                            onManage: { showCategoryManager = true }
                        )
                    }
                }
                .frame(maxHeight: .infinity)

                inputPanel
            }
            .background { AmbientBackground(tint: kind.tint) }
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showCategoryManager) {
                CategoryManagerView(initialKind: kind == .income ? .income : .expense)
            }
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showTags) {
            TagPickerSheet(selection: $tags)
                .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .top) {
            if let savedToast {
                Label(savedToast, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.tint(Color.income.opacity(0.25)), in: .capsule)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear(perform: applyDefaults)
        .onChange(of: kind) { _, newKind in
            Haptics.tap()
            if newKind != .transfer, category?.kind != newKind {
                category = categories.first { $0.kind == newKind }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    photo = ImageTools.compress(data)
                }
            }
        }
        .confirmationDialog("删除这笔账单？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let record = request.record {
                    dismiss()
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        context.delete(record)
                        try? context.save()
                    }
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("关闭", systemImage: "xmark", role: .close) { dismiss() }
        }
        ToolbarItem(placement: .principal) {
            Picker("类型", selection: $kind) {
                ForEach(RecordKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
        }
        if isEditing {
            ToolbarItem(placement: .destructiveAction) {
                Button("删除", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
    }

    // MARK: Input panel

    private var inputPanel: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("添加备注…", text: $note)
                    .focused($noteFocused)
                    .submitLabel(.done)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .glassEffect(.regular.interactive(), in: .capsule)

                VStack(alignment: .trailing, spacing: 0) {
                    if keypad.hasOperator {
                        Text(keypad.expression)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Text(Money.format(keypad.cents, code: currencyCode))
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(kind.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: keypad.cents)
                        .keyframeAnimator(initialValue: 0.0, trigger: shakeAmount) { content, offset in
                            content.offset(x: offset)
                        } keyframes: { _ in
                            KeyframeTrack {
                                SpringKeyframe(-10, duration: 0.08)
                                SpringKeyframe(10, duration: 0.08)
                                SpringKeyframe(-6, duration: 0.08)
                                SpringKeyframe(0, duration: 0.1)
                            }
                        }
                }
                .frame(minWidth: 120, alignment: .trailing)
            }

            chips

            if !noteFocused {
                KeypadView(
                    input: $keypad,
                    tint: kind.tint,
                    isEditing: isEditing,
                    onDone: { save(again: false) },
                    onAgain: { save(again: true) }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .animation(.smooth, value: noteFocused)
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if kind != .transfer {
                        Menu {
                            Picker("账户", selection: $account) {
                                Text("不选择账户").tag(Account?.none)
                                ForEach(accounts) { item in
                                    Label(item.name, systemImage: item.symbol).tag(Optional(item))
                                }
                            }
                        } label: {
                            GlassChip(title: account?.name ?? "账户",
                                      symbol: account?.symbol ?? "creditcard",
                                      tint: account?.color, isActive: account != nil)
                        }
                    }

                    DatePicker("时间", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)

                    Button {
                        showTags = true
                    } label: {
                        GlassChip(title: tags.isEmpty ? "标签" : tags.map(\.name).joined(separator: "、"),
                                  symbol: "number", tint: .cyan, isActive: !tags.isEmpty)
                    }
                    .buttonStyle(.plain)

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        GlassChip(title: photo == nil ? "票据" : "已附图",
                                  symbol: photo == nil ? "camera" : "photo.fill",
                                  tint: .purple, isActive: photo != nil)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if photo != nil {
                            Button("移除图片", systemImage: "trash", role: .destructive) {
                                photo = nil
                                photoItem = nil
                            }
                        }
                    }

                    Button {
                        excluded.toggle()
                        Haptics.tap()
                    } label: {
                        GlassChip(title: excluded ? "不计入统计" : "计入统计",
                                  symbol: excluded ? "eye.slash" : "eye",
                                  tint: .orange, isActive: excluded)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Actions

    private func applyDefaults() {
        guard !isEditing else { return }
        if account == nil {
            account = accounts.first { $0.uuid == settings.defaultAccountID } ?? accounts.first
        }
        if kind == .transfer {
            if toAccount == nil { toAccount = accounts.first { $0.uuid != account?.uuid } }
        } else if category == nil {
            category = kindCategories.first
        }
    }

    private func save(again: Bool) {
        if keypad.hasOperator {
            keypad.commit()
            Haptics.tap()
            return
        }
        let cents = keypad.cents
        guard cents > 0 else {
            Haptics.warning()
            shakeAmount += 1
            return
        }
        if kind == .transfer {
            guard let from = account, let to = toAccount, from.uuid != to.uuid else {
                Haptics.warning()
                shakeAmount += 1
                return
            }
        }

        let record: Record
        if let existing = request.record {
            record = existing
        } else {
            record = Record(kind: kind, amountCents: cents, ledgerID: settings.currentLedgerID)
            context.insert(record)
        }
        record.kind = kind
        record.amountCents = cents
        record.date = date
        record.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        record.account = account
        record.currencyCode = currencyCode
        record.excludedFromStats = excluded
        record.photo = photo
        record.tags = tags
        record.updatedAt = .now
        if kind == .transfer {
            record.category = nil
            record.toAccount = toAccount
            record.feeCents = feeCents
            record.toAmountCents = (toAccount?.currencyCode != account?.currencyCode) ? toAmountCents : 0
        } else {
            record.category = category ?? kindCategories.first
            record.toAccount = nil
            record.feeCents = 0
            record.toAmountCents = 0
        }
        try? context.save()
        Haptics.success()

        if (again || settings.continuousEntry) && !isEditing {
            let message = "已记录 \(record.displayTitle) \(Money.format(cents, code: currencyCode))"
            withAnimation(.smooth) {
                keypad.clear()
                note = ""
                photo = nil
                photoItem = nil
                feeCents = 0
                toAmountCents = 0
                savedToast = message
            }
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.smooth) {
                    if savedToast == message { savedToast = nil }
                }
            }
        } else {
            dismiss()
        }
    }
}

// MARK: - Category grid

struct CategoryGrid: View {
    let categories: [BillCategory]
    @Binding var selection: BillCategory?
    var onManage: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(categories) { category in
                    let isSelected = selection?.uuid == category.uuid
                    Button {
                        withAnimation(.snappy) { selection = category }
                        Haptics.tap()
                    } label: {
                        VStack(spacing: 6) {
                            CategoryIcon(symbol: category.symbol, color: category.color, size: 50, filled: isSelected)
                                .scaleEffect(isSelected ? 1.08 : 1)
                            Text(category.name)
                                .font(.caption)
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onManage) {
                    VStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 50, height: 50)
                            .glassEffect(.regular.interactive(), in: .circle)
                        Text("管理")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }
}

// MARK: - Transfer panel

struct TransferPanel: View {
    let accounts: [Account]
    @Binding var from: Account?
    @Binding var to: Account?
    @Binding var feeCents: Int
    @Binding var toAmountCents: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassEffectContainer(spacing: 14) {
                    VStack(spacing: 10) {
                        accountCard(title: "转出", selection: $from)
                        Button {
                            withAnimation(.bouncy) {
                                let previous = from
                                from = to
                                to = previous
                            }
                            Haptics.tap()
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.headline)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        accountCard(title: "转入", selection: $to)
                    }
                }

                VStack(spacing: 0) {
                    CentsField(title: "手续费", cents: $feeCents, code: from?.currencyCode ?? AppSettings.shared.baseCurrency)
                        .padding(.vertical, 10)
                    if let from, let to, from.currencyCode != to.currencyCode {
                        Divider()
                        CentsField(title: "到账金额", cents: $toAmountCents, code: to.currencyCode)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 16)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))

                if from != nil, from?.uuid == to?.uuid {
                    Label("转出与转入账户不能相同", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .padding(16)
        }
    }

    private func accountCard(title: String, selection: Binding<Account?>) -> some View {
        Menu {
            Picker(title, selection: selection) {
                ForEach(accounts) { account in
                    Label("\(account.name)  \(Money.format(account.balanceCents, code: account.currencyCode))",
                          systemImage: account.symbol)
                        .tag(Optional(account))
                }
            }
        } label: {
            HStack(spacing: 14) {
                CategoryIcon(symbol: selection.wrappedValue?.symbol ?? "questionmark",
                             color: selection.wrappedValue?.color ?? .gray, size: 44, filled: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(selection.wrappedValue?.name ?? "选择账户").font(.headline)
                }
                Spacer()
                if let account = selection.wrappedValue {
                    Text(Money.format(account.balanceCents, code: account.currencyCode))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .contentShape(.rect)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Image helpers

enum ImageTools {
    /// Downscales and re-encodes a photo so receipts stay small in iCloud.
    static func compress(_ data: Data, maxDimension: CGFloat = 1600) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let rendered = image.preparingThumbnail(of: target) ?? image
        return rendered.jpegData(compressionQuality: 0.72)
    }
}
