import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Background

struct BackgroundSettingsView: View {
    @State private var store = BackgroundStore.shared
    @State private var photoItem: PhotosPickerItem?
    @State private var importingFile = false
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        @Bindable var store = store

        List {
            Group {
                ZStack {
                    AmbientBackground()
                    VStack(spacing: 10) {
                        Text("¥1,286.40")
                            .font(.money(30))
                        Text("本月支出预览").font(Font.skin(.caption)).foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    if loading { ProgressView().controlSize(.large) }
                }
                .frame(height: 300)
                .clipShape(.rect(cornerRadius: 28))
                .plainListRow(top: 8, bottom: 8)

                Section {
                    PhotosPicker(selection: $photoItem, matching: .any(of: [.images, .videos])) {
                        Label("从相册选择图片 / GIF / 视频", systemImage: "photo.on.rectangle.angled")
                    }
                    Button {
                        importingFile = true
                    } label: {
                        Label("从「文件」导入", systemImage: "folder")
                    }
                    if store.isActive {
                        Button("恢复默认渐变背景", role: .destructive) { store.reset() }
                    }
                } footer: {
                    Text("支持 JPG / PNG / HEIC 图片、GIF 动图和 MP4 / MOV 视频。视频会静音循环播放，不会打断你正在听的音乐。")
                }

                if store.isActive {
                    Section {
                        VStack(alignment: .leading) {
                            Text("模糊 \(Int(store.blur))")
                            Slider(value: $store.blur, in: 0...30)
                        }
                        VStack(alignment: .leading) {
                            Text("暗化 \(Int(store.dim * 100))%")
                            Slider(value: $store.dim, in: 0...0.8)
                        }
                        Toggle("叠加彩色光晕", isOn: $store.tintOverlay)
                    Toggle("通透玻璃（列表更透明）", isOn: $store.clearGlass)
                        if store.kind == .video {
                            Toggle("播放视频", isOn: Binding(
                                get: { store.playVideo },
                                set: { store.playVideo = $0; BackgroundVideoPlayer.shared.setActive($0) }
                            ))
                        }
                    } header: {
 SectionTitle("效果")
 }
                }
            }
            .listRowBackground(GlassRowBackground())
        }
        .pageBackground()
        .navigationTitle("自定义背景")
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.image, .gif, .movie, .mpeg4Movie, .quickTimeMovie]) { result in
            guard case .success(let url) = result else { return }
            importFile(url)
        }
        .alert("无法使用这个文件", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        loading = true
        defer { loading = false; photoItem = nil }
        do {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { return }
                try store.setVideo(from: movie.url)
            } else if let data = try await item.loadTransferable(type: Data.self) {
                try store.setImage(data: data)
            }
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func importFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let type = UTType(filenameExtension: url.pathExtension) ?? .data
            if type.conforms(to: .movie) {
                try store.setVideo(from: url)
            } else {
                try store.setImage(data: Data(contentsOf: url))
            }
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - App icon

struct AppIconPickerView: View {
    @State private var current = UIApplication.shared.alternateIconName
    @State private var error: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(AppIconOption.all) { option in
                    Button {
                        select(option)
                    } label: {
                        VStack(spacing: 8) {
                            Image(option.preview)
                                .resizable()
                                .scaledToFit()
                                .clipShape(.rect(cornerRadius: 22))
                                .overlay {
                                    if current == option.iconName {
                                        RoundedRectangle(cornerRadius: 22)
                                            .strokeBorder(Color.accentColor, lineWidth: 3)
                                    }
                                }
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                            Text(option.title)
                                .font(Font.skin(.footnote).weight(current == option.iconName ? .semibold : .regular))
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            Text("iOS 只允许切换 App 内置的图标，无法使用相册照片作为桌面图标。分类、账户、账本图标则可以使用任意 Emoji。")
                .font(Font.skin(.footnote))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
        }
        .background { AmbientBackground() }
        .navigationTitle("App 图标")
        .alert("切换失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func select(_ option: AppIconOption) {
        guard UIApplication.shared.supportsAlternateIcons else {
            error = "当前环境不支持切换图标"
            return
        }
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(option.iconName)
                current = option.iconName
                Haptics.success()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Members

struct MembersView: View {
    @Environment(AppSettings.self) private var settings
    @State private var newName = ""

    var body: some View {
        List {
            Group {
                Section {
                    HStack {
                        TextField("添加成员，如「我」「老婆」「宝宝」", text: $newName)
                            .onSubmit(add)
                        Button("添加", action: add).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    ForEach(settings.members, id: \.self) { name in
                        Label(name, systemImage: "person.crop.circle")
                    }
                    .onDelete { settings.members.remove(atOffsets: $0) }
                    .onMove { settings.members.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("添加成员后，记账面板会出现「成员」选项，统计页可以按成员筛选，适合家庭共用一个账本。")
                }
            }
            .listRowBackground(GlassRowBackground())
        }
        .pageBackground()
        .navigationTitle("家庭成员")
        .toolbar { EditButton() }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !settings.members.contains(name) else { return }
        settings.members.append(name)
        newName = ""
    }
}

// MARK: - Reminders

struct ReminderSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var denied = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Group {
                Section {
                    Toggle("每日记账提醒", isOn: $settings.dailyReminderEnabled)
                    if settings.dailyReminderEnabled {
                        DatePicker("提醒时间", selection: Binding(
                            get: {
                                Calendar.current.date(bySettingHour: settings.dailyReminderMinutes / 60,
                                                      minute: settings.dailyReminderMinutes % 60, second: 0, of: .now) ?? .now
                            },
                            set: {
                                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                                settings.dailyReminderMinutes = (c.hour ?? 21) * 60 + (c.minute ?? 0)
                            }
                        ), displayedComponents: .hourAndMinute)
                    }
                    NavigationLink { BudgetAlertsView() } label: {
                    LabeledContent("预算警报", value: settings.budgetAlertsEnabled
                        ? settings.budgetThresholds.map { "\($0)%" }.joined(separator: " / ") : "已关闭")
                }
                    Toggle("信用卡还款提醒（提前 2 天）", isOn: $settings.creditDueAlertsEnabled)
                } footer: {
                    Text(denied ? "通知权限已关闭，请到「设置 > 通知 > MoonMoney」开启。" : "提醒全部在本机生成，不会上传任何数据。")
                }
            }
            .listRowBackground(GlassRowBackground())
        }
        .pageBackground()
        .navigationTitle("提醒")
        .task {
            denied = !(await Notifications.requestAuthorization())
        }
        .onChange(of: settings.dailyReminderEnabled) { reschedule() }
        .onChange(of: settings.dailyReminderMinutes) { reschedule() }
        .onChange(of: settings.creditDueAlertsEnabled) { reschedule() }
    }

    private func reschedule() {
        Task { await Notifications.reschedule(context: context) }
    }
}

// MARK: - Auto bookkeeping guide

struct AutoBookkeepingGuideView: View {
    var body: some View {
        List {
            Group {
                Section {
                    step(1, "打开「快捷指令」App → 自动化 → 新建自动化")
                    step(2, "选择「钱包」→ 选择你的卡片 → 勾选「立即运行」")
                    step(3, "添加操作「MoonMoney · 记一笔」")
                    step(4, "把「金额」设为快捷指令输入的「金额」，「商户」设为「商户」")
                } header: {
                    Label("Apple Pay 刷卡自动记账", systemImage: "wallet.pass.fill")
                } footer: {
                    Text("每次用 Apple Pay 付款后会自动记一笔，并根据商户和你的历史习惯判断分类。")
                }

                Section {
                    step(1, "设置 → 辅助功能 → 触控 → 轻点背面 → 轻点两下")
                    step(2, "选择一个快捷指令：先「截屏」，再「MoonMoney · 截图记账」")
                    step(3, "在支付宝、微信付款成功页轻点手机背面两下即可")
                } header: {
                    Label("轻点背面截图记账", systemImage: "hand.tap.fill")
                } footer: {
                    Text("截图会在本机用 Vision 识别金额和商户，不会上传。也可以在相册里分享截图到快捷指令。")
                }

                Section {
                    step(1, "对 Siri 说：“用 MoonMoney 智能记账”")
                    step(2, "说出内容，例如：“午饭 32，打车 18 用微信”")
                } header: {
                    Label("Siri 一句话记账", systemImage: "waveform")
                }

                Section {
                    step(1, "设置 → 操作按钮 → 控制 → 搜索「MoonMoney」→ 记一笔")
                    step(2, "控制中心编辑 → 添加控制 → MoonMoney")
                } header: {
                    Label("操作按钮 & 控制中心", systemImage: "button.horizontal.top.press.fill")
                }

                Section {
                    Link(destination: URL(string: "shortcuts://")!) {
                        Label("打开快捷指令", systemImage: "arrow.up.forward.app")
                    }
                }
            }
            .listRowBackground(GlassRowBackground())
        }
        .pageBackground()
        .navigationTitle("自动记账")
    }

    private func step(_ index: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(Font.skin(.caption).bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.gradient, in: .circle)
            Text(text).font(Font.skin(.subheadline))
        }
    }
}
