import PhotosUI
import SwiftUI
import UIKit

// MARK: - Glass card

extension View {
    /// A floating Liquid Glass panel used for hero cards.
    func glassCard(cornerRadius: CGFloat = 28, tint: Color? = nil, padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
    }

    /// Clears list row chrome so a custom card can sit directly on the background.
    func plainListRow(top: CGFloat = 6, bottom: CGFloat = 6) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - Controls that sit inside a glass card

/// Liquid Glass should never be stacked on Liquid Glass. Buttons placed inside a
/// `glassCard` use this flat, vibrant fill instead of `.glass`.
struct InCardButtonStyle: ButtonStyle {
    var prominent = false
    var circle = false

    func makeBody(configuration: Configuration) -> some View {
        InCardButtonBody(configuration: configuration, prominent: prominent, circle: circle)
    }
}

private struct InCardButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let circle: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, circle ? 0 : 14)
            .frame(minWidth: 34, minHeight: 34)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                if circle {
                    Circle().fill(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary))
                } else {
                    Capsule().fill(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary))
                }
            }
            .contentShape(circle ? AnyShape(Circle()) : AnyShape(Capsule()))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == InCardButtonStyle {
    /// Flat fill for controls inside a glass card.
    static func inCard(prominent: Bool = false, circle: Bool = false) -> InCardButtonStyle {
        InCardButtonStyle(prominent: prominent, circle: circle)
    }
}

// MARK: - Glass list rows

/// Row background for List / Form: Liquid Glass instead of the opaque
/// system cell, so the page background shows through every section.
struct GlassRowBackground: View {
    var body: some View {
        Rectangle()
            .fill(.clear)
            .glassEffect(BackgroundStore.shared.clearGlass ? .clear : .regular, in: .rect)
    }
}

// MARK: - Page background

extension View {
    /// Applies the user's page background (custom image / GIF / video, or the default mesh)
    /// behind a List, Form or ScrollView.
    func pageBackground(tint: Color = .accentColor) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background { AmbientBackground(tint: tint) }
    }
}

// MARK: - Ambient background

/// Soft mesh gradient that gives Liquid Glass something colorful to refract.
struct AmbientBackground: View {
    var tint: Color = .accentColor
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if BackgroundStore.shared.isActive {
            CustomBackgroundView()
        } else {
            mesh
        }
    }

    private var mesh: some View {
        let base: Color = scheme == .dark ? .black : Color(white: 0.97)
        return MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.45], [0.6, 0.35], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                tint.opacity(scheme == .dark ? 0.55 : 0.45), .purple.opacity(0.35), .orange.opacity(0.30),
                .cyan.opacity(0.25), tint.opacity(0.20), .pink.opacity(0.22),
                base, base, base,
            ]
        )
        .background(base)
        .ignoresSafeArea()
    }
}

// MARK: - Icons

struct CategoryIcon: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 38
    var filled = false
    /// Custom picture icon; takes priority over `symbol`.
    var image: Data? = nil

    var body: some View {
        if let image, let uiImage = IconImageCache.image(for: image) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(.circle)
                .overlay {
                    Circle().strokeBorder(filled ? color : .white.opacity(0.25), lineWidth: filled ? 2.5 : 0.5)
                }
        } else {
            SymbolGlyph(symbol)
                .font(.system(size: size * (SymbolGlyph.isEmoji(symbol) ? 0.52 : 0.44), weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(filled ? .white : color)
                .frame(width: size, height: size)
                .background(filled ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.16)), in: .circle)
        }
    }
}

/// Decodes custom icon images once and keeps them in memory.
enum IconImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for data: Data) -> UIImage? {
        let key = "\(data.count)-\(data.prefix(256).hashValue)-\(data.suffix(256).hashValue)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Center-crops to a square and shrinks to a small PNG (keeps sticker transparency).
    static func makeIcon(from data: Data, side: CGFloat = 180) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let crop = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - crop) / 2, y: (size.height - crop) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let output = renderer.image { _ in
            let scale = side / crop
            image.draw(in: CGRect(x: -origin.x * scale, y: -origin.y * scale,
                                  width: size.width * scale, height: size.height * scale))
        }
        return output.pngData()
    }
}

/// Capsule chip used in the entry sheet.
struct GlassChip: View {
    var title: String
    var symbol: String
    var tint: Color? = nil
    var isActive = false
    /// Set false when the chip sits inside a glass card, to avoid glass-on-glass.
    var glass = true

    var body: some View {
        let label = Label(title, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .foregroundStyle(isActive ? AnyShapeStyle(tint ?? .accentColor) : AnyShapeStyle(.primary))
        if glass {
            label.glassEffect(.regular.tint(isActive ? (tint ?? .accentColor).opacity(0.18) : nil).interactive(), in: .capsule)
        } else {
            label.background(isActive ? AnyShapeStyle((tint ?? .accentColor).opacity(0.16)) : AnyShapeStyle(.fill.tertiary),
                             in: .capsule)
        }
    }
}

struct AmountText: View {
    var cents: Int
    var kind: RecordKind
    var code: String = AppSettings.shared.baseCurrency
    var font: Font = .body

    var body: some View {
        Text(text)
            .font(font.monospacedDigit())
            .fontWeight(.semibold)
            .foregroundStyle(kind == .expense ? Color.primary : kind.tint)
            .contentTransition(.numericText())
    }

    private var text: String {
        switch kind {
        case .expense: "-" + Money.format(cents, code: code)
        case .income: "+" + Money.format(cents, code: code)
        case .transfer: Money.format(cents, code: code)
        }
    }
}

/// Thin progress bar with a glass track.
struct ProgressCapsule: View {
    var value: Double
    var tint: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
                    .opacity(value <= 0 ? 0 : 1)
            }
        }
        .frame(height: height)
        .animation(.smooth, value: value)
    }
}

struct RingGauge: View {
    var value: Double
    var tint: Color
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.smooth, value: value)
    }
}

// MARK: - Pickers

enum SymbolLibrary {
    static let groups: [(String, [String])] = [
        ("餐饮", ["fork.knife", "cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill", "birthday.cake.fill", "wineglass.fill", "mug.fill", "carrot.fill", "fish.fill", "popcorn.fill", "waterbottle.fill"]),
        ("出行", ["car.fill", "tram.fill", "bus.fill", "airplane", "bicycle", "fuelpump.fill", "parkingsign.circle.fill", "ferry.fill", "scooter", "figure.walk"]),
        ("购物", ["bag.fill", "cart.fill", "basket.fill", "tshirt.fill", "shoe.fill", "gift.fill", "giftcard.fill", "handbag.fill", "eyeglasses", "sparkles"]),
        ("居家", ["house.fill", "bolt.fill", "drop.fill", "flame.fill", "wifi", "sofa.fill", "bed.double.fill", "washer.fill", "lightbulb.fill", "key.fill"]),
        ("生活", ["cross.case.fill", "pills.fill", "heart.fill", "figure.run", "dumbbell.fill", "scissors", "pawprint.fill", "leaf.fill", "stroller.fill", "teddybear.fill"]),
        ("娱乐", ["gamecontroller.fill", "film.fill", "music.note", "ticket.fill", "theatermasks.fill", "book.fill", "graduationcap.fill", "paintpalette.fill", "camera.fill", "tv.fill"]),
        ("数码", ["iphone.gen3", "laptopcomputer", "headphones", "applewatch", "desktopcomputer", "keyboard.fill", "printer.fill", "antenna.radiowaves.left.and.right", "icloud.fill", "repeat.circle.fill"]),
        ("金融", ["banknote.fill", "creditcard.fill", "dollarsign.circle.fill", "yensign.circle.fill", "chart.line.uptrend.xyaxis", "building.columns.fill", "briefcase.fill", "star.fill", "envelope.fill", "arrow.uturn.backward.circle.fill"]),
        ("其他", ["tag.fill", "person.2.fill", "hands.clap.fill", "globe.asia.australia.fill", "wrench.and.screwdriver.fill", "doc.text.fill", "moon.stars.fill", "sun.max.fill", "questionmark.circle.fill", "ellipsis.circle.fill"]),
    ]
}

struct SymbolGridPicker: View {
    @Binding var selection: String
    var color: Color
    /// When provided, the user can also pick a photo as the icon.
    var image: Binding<Data?>? = nil
    @State private var emoji = ""
    @State private var photoItem: PhotosPickerItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let image {
                HStack(spacing: 12) {
                    CategoryIcon(symbol: selection, color: color, size: 44, filled: true, image: image.wrappedValue)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(image.wrappedValue == nil ? "用照片做图标" : "更换照片", systemImage: "photo")
                    }
                    .buttonStyle(.inCard())
                    if image.wrappedValue != nil {
                        Button("移除", role: .destructive) { image.wrappedValue = nil }
                            .buttonStyle(.inCard())
                    }
                }
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let icon = IconImageCache.makeIcon(from: data) {
                            image.wrappedValue = icon
                            Haptics.success()
                        }
                        photoItem = nil
                    }
                }
                Text("设置照片后会优先显示照片；选择下方符号或 Emoji 会替换照片。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Emoji").font(.caption).foregroundStyle(.secondary)
                TextField("输入一个表情，如 🍜", text: $emoji)
                    .onChange(of: emoji) { _, value in
                        if let first = value.last, !first.isASCII {
                            selection = String(first)
                            image?.wrappedValue = nil
                            Haptics.tap()
                        }
                    }
                if SymbolGlyph.isEmoji(selection) {
                    CategoryIcon(symbol: selection, color: color, size: 34, filled: true)
                }
            }
            ForEach(SymbolLibrary.groups, id: \.0) { group in
                Text(group.0).font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(group.1, id: \.self) { symbol in
                        Button {
                            selection = symbol
                            image?.wrappedValue = nil
                            Haptics.tap()
                        } label: {
                            CategoryIcon(symbol: symbol, color: color, size: 42, filled: selection == symbol)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct ColorSwatchPicker: View {
    @Binding var hex: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Palette.swatches, id: \.self) { swatch in
                Circle()
                    .fill(Color(hex: swatch).gradient)
                    .frame(height: 30)
                    .overlay {
                        if swatch.caseInsensitiveCompare(hex) == .orderedSame {
                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                        }
                    }
                    .onTapGesture {
                        hex = swatch
                        Haptics.tap()
                    }
            }
        }
        ColorPicker("自定义颜色", selection: Binding(
            get: { Color(hex: hex) },
            set: { hex = $0.hexString }
        ), supportsOpacity: false)
    }
}

/// Text field that edits an amount in cents.
struct CentsField: View {
    var title: String
    @Binding var cents: Int
    var code: String = AppSettings.shared.baseCurrency
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(Money.symbol(for: code)).foregroundStyle(.secondary)
            TextField("0.00", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .focused($focused)
                .frame(maxWidth: 160)
        }
        .onAppear { text = cents == 0 ? "" : Money.plain(cents).replacingOccurrences(of: ",", with: "") }
        .onChange(of: text) { _, newValue in
            let cleaned = newValue.replacingOccurrences(of: ",", with: "")
            if let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) {
                cents = Money.cents(value)
            } else if cleaned.isEmpty || cleaned == "-" {
                cents = 0
            }
        }
    }
}
