import PhotosUI
import SwiftData
import SwiftUI

/// "一句话记账": type or dictate a sentence, or pick a payment screenshot.
struct AIEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<BillCategory> { !$0.isArchived }, sort: \BillCategory.order)
    private var categories: [BillCategory]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.order)
    private var accounts: [Account]

    @State private var text = ""
    @State private var drafts: [RecordDraft] = []
    @State private var engine: ParserEngine?
    @State private var isWorking = false
    @State private var photoItem: PhotosPickerItem?
    @State private var recognized: String?
    @FocusState private var focused: Bool

    private let examples = [
        "午饭 32，打车 18 用微信",
        "昨天超市买菜 126.5，奶茶 15",
        "今天发工资 18500",
        "前天电影票 2 张 90 支付宝",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    inputCard
                    if drafts.isEmpty && !isWorking {
                        examplesCard
                    }
                    ForEach($drafts) { $draft in
                        DraftCard(draft: $draft, categories: categories, accounts: accounts)
                    }
                    if let recognized, !recognized.isEmpty {
                        DisclosureGroup("识别到的文字") {
                            Text(recognized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .glassCard(cornerRadius: 20, padding: 14)
                    }
                }
                .padding(16)
                .padding(.bottom, 80)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { AmbientBackground(tint: .purple) }
            .navigationTitle("AI 记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark", role: .close) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if drafts.contains(where: \.include) {
                    let selected = drafts.filter { $0.include && $0.cents > 0 }
                    Button {
                        SmartParser.save(drafts, context: context)
                        Haptics.success()
                        dismiss()
                    } label: {
                        Label("保存 \(selected.count) 笔 · \(Money.format(selected.reduce(0) { $0 + $1.cents }))",
                              systemImage: "checkmark")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .disabled(selected.isEmpty)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await recognize(item) }
            }
            .onAppear { focused = true }
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(SmartParser.isAIAvailable ? "Apple 智能" : "本地智能规则",
                      systemImage: SmartParser.isAIAvailable ? "apple.intelligence" : "cpu")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SmartParser.isAIAvailable ? AnyShapeStyle(.purple) : AnyShapeStyle(.secondary))
                Spacer()
                if let engine {
                    Text("由「\(engine.rawValue)」解析").font(.caption2).foregroundStyle(.secondary)
                }
            }
            TextField("说一句话，或者点键盘上的麦克风……", text: $text, axis: .vertical)
                .lineLimit(3...6)
                .font(.title3)
                .focused($focused)
                .submitLabel(.go)
                .onSubmit { Task { await parse() } }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("识别截图", systemImage: "text.viewfinder")
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.glass)

                    Spacer()

                    Button {
                        Task { await parse() }
                    } label: {
                        if isWorking {
                            ProgressView().padding(.horizontal, 12)
                        } else {
                            Label("解析", systemImage: "sparkles").padding(.horizontal, 6)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.purple)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                }
            }
        }
        .glassCard(cornerRadius: 28)
    }

    private var examplesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("试试这样说").font(.subheadline.weight(.semibold))
            ForEach(examples, id: \.self) { example in
                Button {
                    text = example
                    Task { await parse() }
                } label: {
                    HStack {
                        Image(systemName: "quote.opening").foregroundStyle(.purple)
                        Text(example).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.left").foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
            Text("也能在「快捷指令」里把支付截图交给 MoonMoney 自动记账。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .glassCard(cornerRadius: 24)
    }

    private func parse() async {
        let input = text
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        focused = false
        isWorking = true
        let result = await SmartParser.parse(input, context: context)
        withAnimation(.smooth) {
            drafts = result.drafts
            engine = result.engine
            isWorking = false
        }
        if result.drafts.isEmpty { Haptics.warning() } else { Haptics.success() }
    }

    private func recognize(_ item: PhotosPickerItem) async {
        isWorking = true
        defer { isWorking = false; photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let result = await SmartParser.parseScreenshot(data, context: context)
        withAnimation(.smooth) {
            recognized = result.text
            drafts = result.drafts
            engine = nil
        }
        if result.drafts.isEmpty { Haptics.warning() } else { Haptics.success() }
    }
}

/// Editable preview of one parsed record.
private struct DraftCard: View {
    @Binding var draft: RecordDraft
    let categories: [BillCategory]
    let accounts: [Account]

    var body: some View {
        let category = categories.first { $0.uuid == draft.categoryID }
        let account = accounts.first { $0.uuid == draft.accountID }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Menu {
                    Picker("分类", selection: $draft.categoryID) {
                        ForEach(categories.filter { $0.kind == draft.kind }) { item in
                            Label(item.name, systemImage: SymbolGlyph.isEmoji(item.symbol) ? "tag" : item.symbol)
                                .tag(Optional(item.uuid))
                        }
                    }
                } label: {
                    CategoryIcon(symbol: category?.symbol ?? "questionmark", color: category?.color ?? .gray, size: 44, filled: true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(category?.name ?? "选择分类").font(.headline)
                    TextField("备注", text: $draft.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $draft.include).labelsHidden()
            }
            HStack(spacing: 8) {
                Picker("类型", selection: $draft.kind) {
                    Text("支出").tag(RecordKind.expense)
                    Text("收入").tag(RecordKind.income)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                .onChange(of: draft.kind) { _, kind in
                    if category?.kind != kind { draft.categoryID = categories.first { $0.kind == kind }?.uuid }
                }

                Menu {
                    Picker("账户", selection: $draft.accountID) {
                        Text("默认账户").tag(UUID?.none)
                        ForEach(accounts) { item in
                            Label(item.name, systemImage: item.symbol).tag(Optional(item.uuid))
                        }
                    }
                } label: {
                    GlassChip(title: account?.name ?? "默认账户", symbol: account?.symbol ?? "creditcard",
                              tint: account?.color, isActive: account != nil)
                }

                Spacer()
                CentsField(title: "", cents: $draft.cents)
                    .frame(width: 120)
            }
            DatePicker("时间", selection: $draft.date, displayedComponents: [.date, .hourAndMinute])
                .font(.subheadline)
        }
        .glassCard(cornerRadius: 24, tint: draft.include ? (category?.color ?? .gray).opacity(0.1) : nil)
        .opacity(draft.include ? 1 : 0.5)
    }
}
