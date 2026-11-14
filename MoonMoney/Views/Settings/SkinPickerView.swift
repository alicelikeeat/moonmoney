import SwiftUI
import UIKit

/// Switch between the Liquid Glass skin and the pixel skin.
struct SkinPickerView: View {
    @Environment(AppSettings.self) private var settings
    @State private var iconMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(Skin.allCases) { skin in
                    Button {
                        guard settings.skin != skin else { return }
                        // Set UIKit fonts first so the rebuilt navigation and tab bars pick them up.
                        PixelChrome.apply(pixel: skin == .pixel)
                        withAnimation(.smooth) { settings.skin = skin }
                        Haptics.success()
                    } label: {
                        SkinPreviewCard(skin: skin, selected: settings.skin == skin)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(skin.title)皮肤\(settings.skin == skin ? "，已选中" : "")")
                }

                if settings.skin == .pixel {
                    fontSection(title: "文字字体", fonts: PixelFont.textFonts, selected: settings.pixelFontRaw,
                                sample: "十一月支出 ¥1,513.06") { id in
                        switchFont { settings.pixelFontRaw = id }
                    }
                    fontSection(title: "金额字体", fonts: PixelFont.moneyFonts, selected: settings.moneyFontRaw,
                                sample: "¥1,513.06", includeFollowText: true) { id in
                        switchFont { settings.moneyFontRaw = id }
                    }

                    Button {
                        setPixelIcon()
                    } label: {
                        Label("同时换上像素 App 图标", systemImage: "app.badge")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.inCard(prominent: true))
                    if let iconMessage {
                        Text(iconMessage).font(Font.skin(.footnote)).foregroundStyle(.secondary)
                    }
                }

                Label(PixelFont.isLoaded ? "像素字体已加载：\(PixelFont.name ?? "")" : "像素字体未加载，已使用等宽字体代替",
                      systemImage: PixelFont.isLoaded ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(Font.skin(.caption))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("像素皮肤会把全部文字（中文、数字、英文，包括导航标题和标签栏）换成像素字体，并把卡片、按钮、进度条、分类图标和背景换成复古像素风格。像素字体基于 GNU Unifont（SIL OFL 1.1 授权）。")
                    .font(Font.skin(.footnote))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .background { AmbientBackground() }
        .navigationTitle("界面皮肤")
    }

    /// Updates UIKit chrome fonts before the change rebuilds the view tree.
    private func switchFont(_ change: () -> Void) {
        change()
        PixelChrome.apply(pixel: true)
        Haptics.tap()
    }

    private func fontSection(title: String, fonts: [PixelFontInfo], selected: String, sample: String,
                             includeFollowText: Bool = false, choose: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Font.skin(.headline))
            if includeFollowText {
                fontRow(title: "跟随文字字体", detail: "金额与正文同一款", sample: sample, fontName: PixelFont.name,
                        size: 22, selected: selected == "body") { choose("body") }
            }
            ForEach(fonts, id: \.id) { info in
                fontRow(title: info.title, detail: info.detail, sample: sample,
                        fontName: PixelFont.postScriptName(info),
                        size: PixelFont.crisp(22 * info.moneyScale, grid: info.grid),
                        selected: selected == info.id) { choose(info.id) }
            }
        }
        .glassCard(cornerRadius: 22, padding: 14)
    }

    private func fontRow(title: String, detail: String, sample: String, fontName: String?, size: CGFloat,
                         selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title).font(Font.skin(.subheadline))
                        Text(detail).font(Font.skin(.caption)).foregroundStyle(.secondary)
                    }
                    Text(sample)
                        .font(fontName.map { .custom($0, fixedSize: size) } ?? .system(size: size, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)\(selected ? "，已选中" : "")")
    }

    private func setPixelIcon() {
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName("AppIcon-Pixel")
                iconMessage = "已换上像素图标"
                Haptics.success()
            } catch {
                iconMessage = "切换失败：\(error.localizedDescription)"
            }
        }
    }
}

/// A miniature of each skin's look.
private struct SkinPreviewCard: View {
    let skin: Skin
    let selected: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(skin.title).font(Font.skin(.headline))
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(Font.skin(.title3))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            ZStack {
                if skin == .pixel {
                    PixelSkyBackground()
                } else {
                    MeshGradient(width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                                 colors: [.indigo.opacity(0.6), .pink.opacity(0.5), .cyan.opacity(0.4), .orange.opacity(0.4)])
                }
                miniCard
                    .padding(20)
            }
            .frame(height: 180)
            .clipShape(skin == .pixel ? AnyShape(PixelRect(step: 6)) : AnyShape(RoundedRectangle(cornerRadius: 22)))
        }
        .padding(16)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 26).strokeBorder(Color.accentColor, lineWidth: 3)
            } else {
                RoundedRectangle(cornerRadius: 26).strokeBorder(.quaternary, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var miniCard: some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            Text("十一月支出").font(Font.skin(.caption)).foregroundStyle(.secondary)
            Text("¥1,654.37")
                .font(skin == .pixel ? Font.money(30) : .system(size: 30, weight: .bold, design: .rounded))
            HStack(spacing: 2) {
                ForEach(0..<12, id: \.self) { index in
                    if skin == .pixel {
                        Rectangle().fill(index < 7 ? Color.income : PixelPalette(scheme: scheme).track).frame(height: 8)
                    }
                }
            }
            .frame(height: skin == .pixel ? 8 : 0)
            if skin == .liquid {
                Capsule().fill(.quaternary).frame(height: 6)
                    .overlay(alignment: .leading) { Capsule().fill(Color.income).frame(width: 140, height: 6) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)

        if skin == .pixel {
            content
                .fontDesign(.monospaced)
                .background { PixelPanel() }
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
    }
}
