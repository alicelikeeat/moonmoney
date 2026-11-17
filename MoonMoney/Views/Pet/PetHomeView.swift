import SwiftData
import SwiftUI

/// 我的宠物：pick a species, name it, and see how it grows with your habits.
struct PetHomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var nameDraft = ""

    var body: some View {
        @Bindable var settings = settings
        let status = PetCenter.shared.status

        ScrollView {
            VStack(spacing: 16) {
                // Stage
                VStack(spacing: 6) {
                    LivePet(size: 140)
                        .frame(maxWidth: .infinity)
                    Text(status.name).font(Font.skin(.title2))
                    Text("\(status.stage.title) · \(status.mood.title)")
                        .font(Font.skin(.subheadline))
                        .foregroundStyle(.secondary)
                    Text("点一点它，会和你说话")
                        .font(Font.skin(.caption))
                        .foregroundStyle(.tertiary)
                }
                .glassCard(cornerRadius: 28)

                // Growth
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("成长").font(Font.skin(.headline))
                        Spacer()
                        Text("经验 \(status.xp)").font(Font.skin(.caption).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    ProgressCapsule(value: status.progress, tint: .orange, height: 10)
                    if let next = status.nextStage {
                        Text(status.stage == .egg ? "记下第一笔账就能孵化"
                             : "再攒 \(max(0, next.threshold - status.xp)) 点经验长成\(next.title)")
                            .font(Font.skin(.caption))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("已经是成年体，戴上了专属饰品！").font(Font.skin(.caption)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 0) {
                        stat("连续记账", "\(status.streak) 天")
                        stat("记账天数", "\(status.recordedDays) 天")
                        stat("今日投喂", "\(status.todayCount) 次")
                    }
                }
                .glassCard(cornerRadius: 24)

                PetSessionCard()

                // Species
                VStack(alignment: .leading, spacing: 12) {
                    Text("选择伙伴").font(Font.skin(.headline))
                    HStack(spacing: 10) {
                        ForEach(PetSpecies.allCases) { species in
                            Button {
                                settings.petCustomID = ""
                                settings.petSpeciesRaw = species.rawValue
                                PetCenter.shared.refresh(context: context)
                                Haptics.tap()
                            } label: {
                                VStack(spacing: 6) {
                                    PetSpriteView(species: species, stage: .adult, expression: .happy)
                                        .frame(width: 64, height: 64)
                                    Text(species.defaultName).font(Font.skin(.caption))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background {
                                    if settings.petCustomID.isEmpty && settings.petSpeciesRaw == species.rawValue {
                                        PixelRect(step: 4).stroke(Color.accentColor, lineWidth: 3)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(species.defaultName)\(settings.petCustomID.isEmpty && settings.petSpeciesRaw == species.rawValue ? "，已选中" : "")")
                        }
                    }
                    HStack {
                        TextField("给它起个名字", text: $nameDraft)
                            .font(Font.skin(.body))
                            .submitLabel(.done)
                            .onSubmit(saveName)
                        Button("保存", action: saveName)
                            .buttonStyle(.inCard(prominent: true))
                            .disabled(nameDraft.trimmingCharacters(in: .whitespaces) == settings.petName)
                    }
                }
                .glassCard(cornerRadius: 24)

                PetCustomSection()

                // Rules
                VStack(alignment: .leading, spacing: 8) {
                    Text("它怎么成长").font(Font.skin(.headline))
                    rule("fork.knife", "每记一笔，它会接住一枚金币，经验 +2")
                    rule("calendar", "每个记账日 +10，连续记账还有额外经验")
                    rule("target", "预算健康它就开心；快超支时它会替你担心")
                    rule("moon.zzz", "两天没记账它会睡着，记一笔就醒")
                    rule("heart", "它不会生病、不会离开，放心养")
                    rule("square.grid.2x2", "主屏和锁屏小组件会显示它，点一下回到这里")
                    rule("photo", "也可以用照片、GIF 或视频做成你自己的像素宠物")
                    Toggle("在界面中显示宠物", isOn: $settings.petEnabled)
                        .font(Font.skin(.body))
                        .padding(.top, 4)
                }
                .glassCard(cornerRadius: 24)
            }
            .padding(16)
        }
        .background { AmbientBackground(tint: .orange) }
        .navigationTitle("我的宠物")
        .onAppear {
            nameDraft = settings.petName.isEmpty ? status.species.defaultName : settings.petName
            PetCenter.shared.refresh(context: context)
        }
    }

    private func saveName() {
        let name = nameDraft.trimmingCharacters(in: .whitespaces)
        settings.petName = name
        PetCenter.shared.refresh(context: context)
        Haptics.success()
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Font.skin(.caption2)).foregroundStyle(.secondary)
            Text(value).font(Font.skin(.subheadline).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rule(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(Font.skin(.footnote))
        } icon: {
            Image(systemName: symbol).foregroundStyle(.orange)
        }
    }
}

/// Starts the Lock Screen / Dynamic Island session for the rest of today.
struct PetSessionCard: View {
    @Environment(\.modelContext) private var context
    @State private var active = false
    @State private var busy = false
    @State private var note: String?
    @State private var snapshot = PetSnapshot.placeholder

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日记账").font(Font.skin(.headline))
                Spacer()
                Text(active ? "灵动岛进行中" : "未开始")
                    .font(Font.skin(.caption))
                    .foregroundStyle(.secondary)
            }
            Text("锁屏和灵动岛会显示今天花了多少、每天还能花多少，以及\(snapshot.name)的心情。每记一笔都会更新，到午夜自动结束。")
                .font(Font.skin(.footnote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                figure("今日支出", Money.format(snapshot.todayExpense, code: snapshot.currency))
                figure(snapshot.monthBudget > 0 ? "每天还可" : "月预算", allowance)
            }
            Button {
                Task { await toggle() }
            } label: {
                Text(active ? "结束今日记账" : "开始今日记账")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.inCard(prominent: !active))
            .disabled(busy)
            if let note {
                Text(note)
                    .font(Font.skin(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard(cornerRadius: 24)
        .task { await reload() }
    }

    private var allowance: String {
        guard snapshot.monthBudget > 0 else { return "未设置" }
        if snapshot.dailyBudget < 0 { return "已超支" }
        return Money.format(snapshot.dailyBudget, code: snapshot.currency)
    }

    private func figure(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Font.skin(.caption2)).foregroundStyle(.secondary)
            Text(value).font(Font.skin(.subheadline).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reload() async {
        await PetActivityController.reconcile()
        PetCenter.shared.refresh(context: context)
        snapshot = PetStateStore.load() ?? PetSnapshotLogic.capture(context: context)
        active = PetSessionStore.isActive()
    }

    private func toggle() async {
        busy = true
        defer { busy = false }
        note = await PetSessionActions.toggle(context: context)
        snapshot = PetStateStore.load() ?? snapshot
        active = PetSessionStore.isActive()
        Haptics.tap()
    }
}
