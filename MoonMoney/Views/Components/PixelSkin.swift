import CoreText
import SwiftUI
import UIKit

// MARK: - Skin

enum Skin: String, CaseIterable, Identifiable {
    case liquid, pixel
    var id: String { rawValue }
    var title: String {
        switch self {
        case .liquid: "液态玻璃"
        case .pixel: "像素"
        }
    }
}

extension AppSettings {
    var skin: Skin {
        get { Skin(rawValue: skinRaw) ?? .liquid }
        set { skinRaw = newValue.rawValue }
    }
}

// MARK: - Palette

/// A small, high-contrast palette in the spirit of 8/16-bit consoles.
struct PixelPalette {
    let scheme: ColorScheme

    var panel: Color { scheme == .dark ? Color(hex: "#262A52") : Color(hex: "#FFF6E0") }
    var panelPressed: Color { scheme == .dark ? Color(hex: "#323770") : Color(hex: "#F3E2B8") }
    var border: Color { scheme == .dark ? Color(hex: "#0B0D24") : Color(hex: "#2B2440") }
    var shadow: Color { scheme == .dark ? Color.black.opacity(0.55) : Color(hex: "#2B2440").opacity(0.85) }
    var highlight: Color { scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.85) }
    var accent: Color { scheme == .dark ? Color(hex: "#FFCD4A") : Color(hex: "#E8505B") }
    var track: Color { scheme == .dark ? Color(hex: "#15183A") : Color(hex: "#E5D3A8") }
}

// MARK: - Shapes

/// A rectangle whose corners are cut in pixel steps instead of rounded.
struct PixelRect: Shape {
    var step: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let s = min(step, rect.width / 4, rect.height / 4)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 2 * s, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - 2 * s, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - 2 * s, y: rect.minY + s))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + 2 * s))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 2 * s))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 2 * s))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: rect.maxY - 2 * s))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: rect.maxY - s))
        p.addLine(to: CGPoint(x: rect.maxX - 2 * s, y: rect.maxY - s))
        p.addLine(to: CGPoint(x: rect.maxX - 2 * s, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + 2 * s, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + 2 * s, y: rect.maxY - s))
        p.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - s))
        p.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - 2 * s))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 2 * s))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 2 * s))
        p.addLine(to: CGPoint(x: rect.minX + s, y: rect.minY + 2 * s))
        p.addLine(to: CGPoint(x: rect.minX + s, y: rect.minY + s))
        p.addLine(to: CGPoint(x: rect.minX + 2 * s, y: rect.minY + s))
        p.closeSubpath()
        return p
    }
}

/// Chunky panel: solid fill, hard border and a blocky drop shadow.
struct PixelPanel: View {
    var fill: Color? = nil
    var step: CGFloat = 4
    var shadowOffset: CGFloat = 4
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = PixelPalette(scheme: scheme)
        ZStack {
            PixelRect(step: step)
                .fill(palette.shadow)
                .offset(x: shadowOffset, y: shadowOffset)
            PixelRect(step: step)
                .fill(fill ?? palette.panel)
            PixelRect(step: step)
                .stroke(palette.border, lineWidth: 3)
        }
    }
}

// MARK: - Buttons

struct PixelButtonStyle: ButtonStyle {
    var prominent = false
    var square = false
    var minHeight: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        PixelButtonBody(configuration: configuration, prominent: prominent, square: square, minHeight: minHeight)
    }
}

private struct PixelButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let square: Bool
    let minHeight: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let palette = PixelPalette(scheme: scheme)
        let pressed = configuration.isPressed
        configuration.label
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, square ? 0 : 12)
            .frame(minWidth: minHeight, minHeight: minHeight)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(Color.primary))
            .background {
                ZStack {
                    PixelRect(step: 3)
                        .fill(palette.shadow)
                        .offset(x: pressed ? 0 : 3, y: pressed ? 0 : 3)
                    PixelRect(step: 3)
                        .fill(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(pressed ? palette.panelPressed : palette.panel))
                    PixelRect(step: 3)
                        .stroke(palette.border, lineWidth: 2.5)
                }
            }
            .offset(x: pressed ? 3 : 0, y: pressed ? 3 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .animation(.linear(duration: 0.05), value: pressed)
    }
}

/// Keypad / control style that follows the active skin.
struct SkinButtonModifier: ViewModifier {
    var prominent = false
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        if AppSettings.shared.isPixelSkin {
            content.buttonStyle(PixelButtonStyle(prominent: prominent, square: true, minHeight: 44))
        } else if prominent {
            content
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: radius))
        } else {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: radius))
        }
    }
}

extension View {
    func skinButton(prominent: Bool = false, radius: CGFloat = 16) -> some View {
        modifier(SkinButtonModifier(prominent: prominent, radius: radius))
    }

    /// Pixelates the view in the pixel skin (pure SwiftUI content only).
    @ViewBuilder
    func pixellated(_ size: CGFloat = 2.5) -> some View {
        if AppSettings.shared.isPixelSkin {
            self.layerEffect(ShaderLibrary.pixellate(.float(size)), maxSampleOffset: .zero)
        } else {
            self
        }
    }

    /// A surface for small controls: glass normally, a chunky panel in the pixel skin.
    @ViewBuilder
    func skinSurface<S: Shape>(_ shape: S, interactive: Bool = true) -> some View {
        if AppSettings.shared.isPixelSkin {
            self.background { PixelPanel(step: 3, shadowOffset: 3) }
        } else {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        }
    }
}

// MARK: - Fonts

/// Makes sure the bundled MoonPixel font is registered and remembers its real name.
enum PixelFont {
    /// PostScript name of the loaded font, or nil if it could not be loaded.
    static let name: String? = {
        if let existing = UIFont.fontNames(forFamilyName: "MoonPixel").first { return existing }
        guard let url = Bundle.main.url(forResource: "MoonPixel", withExtension: "ttf") else { return nil }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if let existing = UIFont.fontNames(forFamilyName: "MoonPixel").first { return existing }
        // Fall back to reading the name straight from the file.
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first,
              let ps = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String else { return nil }
        return UIFont(name: ps, size: 12) != nil ? ps : nil
    }()

    static var isLoaded: Bool { name != nil }
}

extension Font {
    /// Big money figures: the MoonPixel font in the pixel skin, rounded system otherwise.
    static func money(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        if AppSettings.shared.isPixelSkin, let name = PixelFont.name {
            return .custom(name, fixedSize: size * 0.92)
        }
        if AppSettings.shared.isPixelSkin {
            return .system(size: size, weight: .heavy, design: .monospaced)
        }
        return .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

// MARK: - Progress

/// Segmented block bar.
struct PixelProgressBar: View {
    var value: Double
    var tint: Color
    var height: CGFloat = 10
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = PixelPalette(scheme: scheme)
        GeometryReader { geo in
            let segments = max(6, Int(geo.size.width / (height + 2)))
            let lit = Int((Double(segments) * min(max(value, 0), 1)).rounded())
            HStack(spacing: 2) {
                ForEach(0..<segments, id: \.self) { index in
                    Rectangle()
                        .fill(index < lit ? tint : palette.track)
                }
            }
            .padding(2)
            .background(palette.border)
        }
        .frame(height: height + 4)
    }
}

// MARK: - Background

/// Procedural pixel landscape: night sky with stars and moon, or a sunny day.
struct PixelSkyBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let block: CGFloat = 6
            let dark = scheme == .dark
            let bands: [Color] = dark
                ? ["#0B0E2B", "#141A45", "#1E2260", "#2B2775", "#3D2F86", "#523A92"].map(Color.init(hex:))
                : ["#6CC4FF", "#86D0FF", "#9FDBFF", "#B9E6FF", "#D2F0FF", "#E8F8FF"].map(Color.init(hex:))
            let bandHeight = (size.height * 0.75 / CGFloat(bands.count) / block).rounded() * block
            for (index, color) in bands.enumerated() {
                context.fill(Path(CGRect(x: 0, y: CGFloat(index) * bandHeight, width: size.width, height: bandHeight + 1)), with: .color(color))
            }
            context.fill(Path(CGRect(x: 0, y: CGFloat(bands.count) * bandHeight, width: size.width, height: size.height)),
                         with: .color(bands.last ?? .black))

            var rng = SeededGenerator(seed: 42)
            if dark {
                // Stars
                for _ in 0..<70 {
                    let x = (CGFloat.random(in: 0..<size.width, using: &rng) / block).rounded(.down) * block
                    let y = (CGFloat.random(in: 0..<(size.height * 0.6), using: &rng) / block).rounded(.down) * block
                    let big = Int.random(in: 0..<6, using: &rng) == 0
                    let s = big ? block : block / 2
                    context.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(.white.opacity(big ? 0.95 : 0.6)))
                }
                drawDisc(&context, center: CGPoint(x: size.width * 0.78, y: size.height * 0.14), radius: 6, block: block,
                         color: Color(hex: "#FFE9A8"), cut: CGPoint(x: 2.5, y: -1.5), cutColor: bands[1])
            } else {
                drawDisc(&context, center: CGPoint(x: size.width * 0.8, y: size.height * 0.12), radius: 5, block: block,
                         color: Color(hex: "#FFD84A"), cut: nil, cutColor: .clear)
                // Clouds
                for (cx, cy, w) in [(0.15, 0.18, 9), (0.55, 0.28, 12), (0.3, 0.42, 7)] {
                    let origin = CGPoint(x: (size.width * cx / block).rounded() * block, y: (size.height * cy / block).rounded() * block)
                    for row in 0..<3 {
                        let inset = row == 0 ? 2 : (row == 2 ? 1 : 0)
                        let rect = CGRect(x: origin.x + CGFloat(inset) * block, y: origin.y + CGFloat(row) * block,
                                          width: CGFloat(w - inset * 2) * block, height: block)
                        context.fill(Path(rect), with: .color(.white.opacity(0.95)))
                    }
                }
            }

            // Two layers of stepped hills
            let hills: [(Color, CGFloat, CGFloat)] = dark
                ? [(Color(hex: "#1A1D45"), 0.80, 7), (Color(hex: "#0F1230"), 0.88, 11)]
                : [(Color(hex: "#7FD38A"), 0.80, 7), (Color(hex: "#4DB36A"), 0.88, 11)]
            for (color, base, period) in hills {
                var x: CGFloat = 0
                var step = 0
                while x < size.width {
                    let wave = sin(Double(step) / Double(period) * .pi * 2) * 4 + 4
                    let top = (size.height * base / block).rounded() * block - CGFloat(Int(wave)) * block
                    context.fill(Path(CGRect(x: x, y: top, width: block, height: size.height - top)), with: .color(color))
                    x += block
                    step += 1
                }
            }
        }
        .ignoresSafeArea()
    }

    private func drawDisc(_ context: inout GraphicsContext, center: CGPoint, radius: Int, block: CGFloat,
                          color: Color, cut: CGPoint?, cutColor: Color) {
        let cx = (center.x / block).rounded() * block
        let cy = (center.y / block).rounded() * block
        for dy in -radius...radius {
            for dx in -radius...radius where dx * dx + dy * dy <= radius * radius {
                if let cut {
                    let ddx = Double(dx) - cut.x, ddy = Double(dy) - cut.y
                    if ddx * ddx + ddy * ddy <= Double(radius * radius) * 0.75 { continue }
                }
                context.fill(Path(CGRect(x: cx + CGFloat(dx) * block, y: cy + CGFloat(dy) * block, width: block, height: block)),
                             with: .color(color))
            }
        }
    }
}

/// Deterministic random numbers so the sky looks the same every frame.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
