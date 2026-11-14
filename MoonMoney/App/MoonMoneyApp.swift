import CoreSpotlight
import SwiftData
import SwiftUI
import UserNotifications
import WidgetKit

@main
struct MoonMoneyApp: App {
    @State private var settings = AppSettings.shared
    @State private var router = Router.shared
    @State private var lock = AppLock()

    init() {
        DataStore.bootstrap()
        DemoMode.applyIfRequested()
        PixelChrome.apply(pixel: AppSettings.shared.isPixelSkin)
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Default font for every Text without an explicit one (pixel font in the pixel skin).
                .font(Font.skin(.body))
                // UIKit chrome reads its fonts at creation, so rebuild the tree when the skin changes.
                .id("\(settings.skinRaw)-\(settings.pixelFontRaw)-\(settings.moneyFontRaw)")
                .onAppear { PixelChrome.apply(pixel: settings.isPixelSkin) }
                .onChange(of: settings.skinRaw) { PixelChrome.apply(pixel: settings.isPixelSkin) }
                .onChange(of: settings.pixelFontRaw) { PixelChrome.apply(pixel: settings.isPixelSkin) }
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
    /// Only auto-prompt Face ID after a real trip to the background; the
    /// system prompt itself bounces the scene through inactive → active.
    @State private var returnedFromBackground = false

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
        .sheet(isPresented: $router.showAIEntry) {
            AIEntrySheet()
        }
        .sheet(item: $router.detail) { record in
            NavigationStack {
                RecordDetailView(record: record)
            }
        }
        .onOpenURL { url in
            router.handle(url: url)
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
               let record = Spotlight.record(for: id, in: context) {
                router.detail = record
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .moonMoneyPendingAction)) { _ in
            if let action = PendingActions.consume() { router.handle(action) }
        }
        .overlay(alignment: .top) {
            if let banner = router.banner {
                BudgetBannerView(banner: banner) {
                    withAnimation(.smooth) { router.banner = nil }
                    router.tab = .home
                    router.homeRoute = .alerts
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 4)
            }
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
                returnedFromBackground = true
                lock.lockIfNeeded()
                BackgroundVideoPlayer.shared.setActive(false)
                WidgetSync.reload()
            case .active:
                if RecurringEngine.run(in: context) > 0 { WidgetSync.reload() }
                BackgroundVideoPlayer.shared.setActive(true)
                if let action = PendingActions.consume() { router.handle(action) }
                if lock.isLocked && returnedFromBackground {
                    Task { await lock.unlock() }
                }
                returnedFromBackground = false
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
        HStack(spacing: 4) {
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
                        .font(Font.skin(.subheadline).monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText())
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("今日支出 · \(today.count) 笔")
                            .font(Font.skin(.caption2))
                            .foregroundStyle(.secondary)
                        Text(Money.format(spent))
                            .font(Font.skin(.subheadline).monospacedDigit().weight(.semibold))
                            .contentTransition(.numericText())
                    }
                }
                Spacer(minLength: 4)
                if placement == .inline {
                    Image(systemName: "plus")
                        .font(Font.skin(.subheadline).weight(.bold))
                } else {
                    Label("记一笔", systemImage: "plus")
                        .font(Font.skin(.subheadline).weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.leading, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("记一笔，今日支出 \(Money.format(spent))")

        Button {
            Haptics.tap()
            router.showAIEntry = true
        } label: {
            Image(systemName: "sparkles")
                .font(Font.skin(.subheadline).weight(.semibold))
                .foregroundStyle(.purple)
                .frame(width: 36, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 10)
        .accessibilityLabel("AI 记账")
        }
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
                    .font(Font.skin(.title2).bold())
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

enum WidgetSync {
    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
