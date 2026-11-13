import SwiftData
import SwiftUI

/// 预算警报：live status of every budget plus alert settings.
struct BudgetAlertsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        BudgetAlertsContent(ledgerID: settings.currentLedgerID)
            .id(settings.currentLedgerID)
            .navigationTitle("预算警报")
    }
}

private struct BudgetAlertsContent: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query private var budgets: [Budget]
    @Query private var records: [Record]
    private let interval = Periods.month(containing: .now)
    private let options = [50, 70, 80, 90, 100]

    init(ledgerID: UUID?) {
        let interval = Periods.month(containing: .now)
        let start = interval.start, end = interval.end
        _budgets = Query(filter: #Predicate<Budget> { $0.ledgerID == ledgerID }, sort: \Budget.createdAt)
        _records = Query(filter: #Predicate<Record> {
            $0.date >= start && $0.date < end && $0.ledgerID == ledgerID && $0.kindRaw == 0
        })
    }

    var body: some View {
        @Bindable var settings = settings
        let statuses = BudgetMonitor.statuses(budgets: budgets, records: records, interval: interval)
        let worst = statuses.map(\.level).max() ?? .ok

        List {
            Group {
                VStack(alignment: .leading, spacing: 10) {
                    Label(summaryTitle(worst, count: statuses.filter { $0.level >= .warning }.count),
                          systemImage: worst.symbol)
                        .font(.headline)
                        .foregroundStyle(worst.tint)
                    Text("剩余 \(Periods.remainingDays(in: interval)) 天 · 共 \(statuses.count) 个预算")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .glassCard(cornerRadius: 28, tint: worst.tint.opacity(0.12))
                .plainListRow(top: 8, bottom: 8)

                Section("状态") {
                    if statuses.isEmpty {
                        NavigationLink { BudgetView() } label: {
                            Label("还没有预算，去设置", systemImage: "target")
                        }
                    }
                    ForEach(statuses) { status in
                        BudgetStatusRow(status: status) { enabled in
                            status.budget.alertsEnabled = enabled
                            try? context.save()
                        }
                    }
                }

                Section {
                    ForEach(options, id: \.self) { value in
                        Toggle("用到 \(value)% 时提醒", isOn: Binding(
                            get: { settings.budgetThresholds.contains(value) },
                            set: { on in
                                var set = Set(settings.budgetThresholds)
                                if on { set.insert(value) } else { set.remove(value) }
                                settings.budgetThresholds = set.isEmpty ? [100] : set.sorted()
                            }
                        ))
                    }
                    Toggle("超支预测提醒", isOn: $settings.budgetPaceAlerts)
                    Toggle("开启预算警报", isOn: $settings.budgetAlertsEnabled)
                } header: {
                    Text("提醒规则")
                } footer: {
                    Text("每个阈值每月只提醒一次。超支预测会根据当前花钱速度，在预计月底前用完时提醒（每周最多一次）。App 打开时显示顶部横幅，关闭时发送通知。")
                }
            }
            .listRowBackground(GlassRowBackground())
        }
        .pageBackground(tint: worst.tint)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { BudgetView() } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("编辑预算")
            }
        }
        .task { _ = await Notifications.requestAuthorization() }
    }

    private func summaryTitle(_ level: BudgetStatus.Level, count: Int) -> String {
        switch level {
        case .ok: "所有预算都很健康"
        case .watch: "预算在正常消耗中"
        case .warning: "\(count) 个预算需要注意"
        case .over: "有预算已经超支"
        }
    }
}

struct BudgetStatusRow: View {
    let status: BudgetStatus
    var onToggle: ((Bool) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                CategoryIcon(symbol: status.symbol, color: status.color, size: 36, image: status.image)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.name).font(.subheadline.weight(.semibold))
                    Text("\(Money.format(status.spent)) / \(Money.format(status.limit))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: status.level.symbol)
                    .foregroundStyle(status.level.tint)
                    .accessibilityHidden(true)
                if let onToggle {
                    Toggle("提醒", isOn: Binding(get: { status.budget.alertsEnabled }, set: onToggle))
                        .labelsHidden()
                }
            }
            ProgressCapsule(value: status.ratio, tint: status.level.tint, height: 6)
            if let forecast = status.forecast {
                Label(forecast, systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(status.level.tint)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.headline)，\(status.forecast ?? "")")
    }
}

/// Compact warning strip for the home screen.
struct BudgetWarningStrip: View {
    let statuses: [BudgetStatus]

    var body: some View {
        let alerts = statuses.filter { $0.level >= .warning }.prefix(2)
        if !alerts.isEmpty {
            NavigationLink(value: HomeRoute.alerts) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(alerts)) { status in
                        HStack(spacing: 10) {
                            Image(systemName: status.level.symbol)
                                .foregroundStyle(status.level.tint)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(status.headline).font(.subheadline.weight(.semibold))
                                if let forecast = status.forecast {
                                    Text(forecast).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .glassCard(cornerRadius: 22, tint: (alerts.first?.level.tint ?? .orange).opacity(0.14), padding: 14)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Top-of-screen banner shown when a budget threshold is crossed in the app.
struct BudgetBannerView: View {
    let banner: BudgetBanner
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: banner.level.symbol)
                    .font(.title3)
                    .foregroundStyle(banner.level.tint)
                    .symbolEffect(.bounce, value: banner.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.title).font(.subheadline.weight(.semibold))
                    Text(banner.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(banner.level.tint.opacity(0.18)).interactive(), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .accessibilityLabel("\(banner.title)，\(banner.message)")
    }
}
