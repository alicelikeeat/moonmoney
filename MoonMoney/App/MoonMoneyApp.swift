import SwiftData
import SwiftUI

@main
struct MoonMoneyApp: App {
    @State private var settings = AppSettings.shared
    @State private var router = Router.shared
    @State private var lock = AppLock()

    init() {
        DataStore.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(router)
                .environment(lock)
        }
        .modelContainer(DataStore.container)
    }
}

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Namespace private var entryNamespace

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.tab) {
            Tab("明细", systemImage: "list.bullet.rectangle.portrait", value: AppTab.home) {
                HomeView()
            }
            Tab("统计", systemImage: "chart.pie", value: AppTab.stats) {
                StatsView()
            }
            Tab("资产", systemImage: "wallet.bifold", value: AppTab.assets) {
                AccountsView()
            }
            Tab("我的", systemImage: "person.crop.circle", value: AppTab.me) {
                SettingsView()
            }
            Tab("搜索", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            QuickEntryAccessory()
                .matchedTransitionSource(id: "entry", in: entryNamespace)
        }
        .sheet(item: $router.entry) { request in
            EntrySheet(request: request)
                .navigationTransition(.zoom(sourceID: "entry", in: entryNamespace))
        }
        .overlay {
            if lock.isLocked {
                LockScreen()
                    .transition(.opacity)
            }
        }
        .overlay {
            // Hide amounts in the app switcher when the lock is on.
            if scenePhase != .active && AppSettings.shared.lockEnabled && !lock.isLocked {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                lock.lockIfNeeded()
            case .active:
                RecurringEngine.run(in: context)
                if lock.isLocked {
                    Task { await lock.unlock() }
                }
            default:
                break
            }
        }
        .task {
            if lock.isLocked { await lock.unlock() }
        }
    }
}

/// Persistent "记一笔" bar above the tab bar (iOS 26 bottom accessory).
struct QuickEntryAccessory: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        TodaySpendBar(ledgerID: settings.currentLedgerID)
            .id(settings.currentLedgerID)
    }
}

private struct TodaySpendBar: View {
    @Environment(Router.self) private var router
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Query private var today: [Record]

    init(ledgerID: UUID?) {
        let start = Calendar.current.startOfDay(for: .now)
        let end = start.addingTimeInterval(86_400)
        _today = Query(filter: #Predicate<Record> {
            $0.date >= start && $0.date < end && $0.ledgerID == ledgerID
        })
    }

    var body: some View {
        let spent = Stats.summary(today).expense
        Button {
            Haptics.tap()
            router.newRecord()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: today.count)
                if placement == .inline {
                    Text(Money.format(spent))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText())
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("今日支出 · \(today.count) 笔")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(Money.format(spent))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .contentTransition(.numericText())
                    }
                }
                Spacer(minLength: 4)
                Label("记一笔", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
            }
            .padding(.horizontal, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("记一笔，今日支出 \(Money.format(spent))")
    }
}

struct LockScreen: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        ZStack {
            AmbientBackground()
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse)
                Text("MoonMoney 已锁定")
                    .font(.title2.bold())
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("使用\(lock.biometryName)解锁", systemImage: lock.biometrySymbol)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
    }
}
