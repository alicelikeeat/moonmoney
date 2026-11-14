import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query private var allRecords: [Record]
    @Query(sort: \Ledger.order) private var ledgers: [Ledger]

    @State private var message: String?

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            List {
                Group {
                    profileCard
                        .plainListRow(top: 8, bottom: 8)

                    Section("智能") {
                        Button {
                            Router.shared.showAIEntry = true
                        } label: {
                            SettingsLabel("AI 一句话记账", symbol: "sparkles", color: .purple)
                        }
                        NavigationLink { AutoBookkeepingGuideView() } label: {
                            SettingsLabel("自动记账（Apple Pay / 截图）", symbol: "bolt.fill", color: .orange)
                        }
                        NavigationLink { MoneyMapView() } label: {
                            SettingsLabel("资金三维地图", symbol: "cube.transparent.fill", color: .teal)
                        }
                        NavigationLink { ReportsView() } label: {
                            SettingsLabel("月报与年度账单", symbol: "doc.richtext.fill", color: .pink)
                        }
                        Toggle(isOn: $settings.aiEnabled) {
                            SettingsLabel("使用 Apple 智能", symbol: "apple.intelligence", color: .indigo,
                                          subtitle: "状态：\(SmartParser.aiStatusText)")
                        }
                    }

                    Section("理财") {
                        NavigationLink { SavingsGoalsView() } label: {
                            SettingsLabel("存钱目标", symbol: "star.circle.fill", color: .orange)
                        }
                        NavigationLink { DebtsView() } label: {
                            SettingsLabel("借贷", symbol: "person.2.fill", color: .teal)
                        }
                        NavigationLink { ReimbursementsView() } label: {
                            SettingsLabel("报销", symbol: "doc.text.fill", color: .cyan)
                        }
                    }

                    Section("个性化") {
                        NavigationLink { SkinPickerView() } label: {
                            SettingsLabel("界面皮肤", symbol: "square.grid.3x3.fill", color: .orange,
                                          subtitle: settings.skin.title)
                        }
                        NavigationLink { BackgroundSettingsView() } label: {
                            SettingsLabel("自定义背景（图片 / GIF / 视频）", symbol: "photo.fill", color: .pink)
                        }
                        NavigationLink { AppIconPickerView() } label: {
                            SettingsLabel("App 图标", symbol: "app.badge.fill", color: .blue)
                        }
                        NavigationLink { MembersView() } label: {
                            SettingsLabel("家庭成员", symbol: "person.3.fill", color: .green)
                        }
                        NavigationLink { ReminderSettingsView() } label: {
                            SettingsLabel("提醒", symbol: "bell.badge.fill", color: .red)
                        }
                    }

                    Section("记账") {
                        NavigationLink { BudgetView() } label: {
                            SettingsLabel("预算", symbol: "target", color: .green)
                        }
                        NavigationLink { BudgetAlertsView() } label: {
                            SettingsLabel("预算警报", symbol: "bell.badge.fill", color: .red)
                        }
                        NavigationLink { RecurringListView() } label: {
                            SettingsLabel("周期记账", symbol: "repeat", color: .purple)
                        }
                        NavigationLink { CategoryManagerView(initialKind: .expense) } label: {
                            SettingsLabel("分类管理", symbol: "square.grid.2x2.fill", color: .orange)
                        }
                        NavigationLink { TagManagerView() } label: {
                            SettingsLabel("标签管理", symbol: "number", color: .cyan)
                        }
                        NavigationLink { LedgerManagerView() } label: {
                            SettingsLabel("账本管理", symbol: "books.vertical.fill", color: .indigo)
                        }
                    }

                    Section("偏好") {
                        Picker(selection: $settings.baseCurrency) {
                            ForEach(Currencies.common, id: \.self) { code in
                                Text("\(code) · \(Currencies.name(code))").tag(code)
                            }
                        } label: {
                            SettingsLabel("本位币", symbol: "yensign.circle.fill", color: .yellow)
                        }
                        NavigationLink { ExchangeRatesView() } label: {
                            SettingsLabel("汇率", symbol: "arrow.left.arrow.right.circle.fill", color: .teal)
                        }
                        Picker(selection: $settings.monthStartDay) {
                            ForEach(1...28, id: \.self) { day in
                                Text("每月 \(day) 日").tag(day)
                            }
                        } label: {
                            SettingsLabel("每月起始日", symbol: "calendar.badge.clock", color: .red)
                        }
                        Toggle(isOn: $settings.weekStartsOnMonday) {
                            SettingsLabel("每周从周一开始", symbol: "calendar", color: .blue)
                        }
                        Toggle(isOn: $settings.recordLocation) {
                            SettingsLabel("记账时记录位置", symbol: "location.fill", color: .blue, subtitle: "用于资金地图，仅保存在本机")
                        }
                        Toggle(isOn: $settings.continuousEntry) {
                            SettingsLabel("连续记账", symbol: "square.stack.3d.up.fill", color: .mint)
                        }
                        Toggle(isOn: $settings.hapticsEnabled) {
                            SettingsLabel("触感反馈", symbol: "iphone.radiowaves.left.and.right", color: .pink)
                        }
                    }

                    Section {
                        Toggle(isOn: Binding(
                            get: { settings.lockEnabled },
                            set: { newValue in
                                if newValue {
                                    Task {
                                        if await AppLock.verify() { settings.lockEnabled = true }
                                    }
                                } else {
                                    settings.lockEnabled = false
                                }
                            }
                        )) {
                            SettingsLabel("面容 ID 锁", symbol: "faceid", color: .green)
                        }
                    } header: {
                        Text("隐私")
                    } footer: {
                        Text("开启后，每次回到 App 都需要验证身份，并在多任务界面隐藏金额。")
                    }

                    Section {
                        LabeledContent {
                            Text(iCloudAvailable ? "已登录" : "未登录")
                                .foregroundStyle(iCloudAvailable ? Color.income : Color.secondary)
                        } label: {
                            SettingsLabel("iCloud 同步", symbol: "icloud.fill", color: .blue)
                        }
                        LabeledContent {
                            Text(AppGroup.storeMode.rawValue)
                                .font(.footnote)
                                .foregroundStyle(AppGroup.storeMode == .memory ? Color.expense : Color.secondary)
                        } label: {
                            SettingsLabel("数据存储", symbol: "internaldrive.fill", color: .gray)
                        }
                        NavigationLink { DataManagementView() } label: {
                            SettingsLabel("数据管理（备份 / 恢复 / 清空）", symbol: "tray.full.fill", color: .red)
                        }
                    } header: {
                        Text("数据")
                    } footer: {
                        Text("在 Xcode 中为 App 开启 iCloud（CloudKit）能力后，数据会自动在你的设备间同步。")
                    }

                    Section {
                        LabeledContent("版本", value: appVersion)
                        Link(destination: URL(string: "https://support.apple.com/zh-cn/guide/shortcuts/welcome/ios")!) {
                            SettingsLabel("Siri 与快捷指令：说“用 MoonMoney 记一笔”", symbol: "waveform", color: .indigo)
                        }
                    }
                }
                .listRowBackground(GlassRowBackground())
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(tint: .indigo) }
            .navigationTitle("我的")
            .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var profileCard: some View {
        let cal = Calendar.current
        let days = Set(allRecords.map { cal.startOfDay(for: $0.date) }).count
        let first = allRecords.map(\.date).min()
        return HStack(spacing: 16) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: .rect(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 6) {
                Text("MoonMoney").font(.title3.bold())
                HStack(spacing: 14) {
                    stat("\(days)", "记账天数")
                    stat("\(allRecords.count)", "总笔数")
                    stat("\(ledgers.count)", "账本")
                }
                if let first {
                    Text("始于 \(first.zh("yMMMd"))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .glassCard(cornerRadius: 30)
    }

    private func stat(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct SettingsLabel: View {
    let title: String
    let symbol: String
    let color: Color
    var subtitle: String? = nil

    init(_ title: String, symbol: String, color: Color, subtitle: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.color = color
        self.subtitle = subtitle
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(Color.primary)
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(Color.secondary)
                }
            }
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color.gradient, in: .rect(cornerRadius: 7))
        }
    }
}
