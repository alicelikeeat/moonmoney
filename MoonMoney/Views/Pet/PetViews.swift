import SwiftUI

// MARK: - Static sprite

/// Draws one frame of a pet on a 20×20 pixel grid.
struct PetSpriteView: View {
    let species: PetSpecies
    let stage: PetStage
    var expression: PetExpression = .normal
    var stepB = false
    var flipped = false

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let grid = composeGrid()
            let palette = paletteColors()
            let cell = floor(min(size.width, size.height) / 20 * stage.scale * 2) / 2
            let total = cell * 20
            let originX = (size.width - total) / 2
            let originY = size.height - total
            for (r, row) in grid.enumerated() {
                for (c, code) in row.enumerated() where code != "." {
                    guard let color = palette[code] else { continue }
                    let col = flipped ? 19 - c : c
                    let rect = CGRect(x: originX + CGFloat(col) * cell, y: originY + CGFloat(r) * cell,
                                      width: cell + 0.5, height: cell + 0.5)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func paletteColors() -> [Character: Color] {
        if stage == .egg {
            let spot = species.sheet.palette["b"].map(Color.init(hex:)) ?? .pink
            return ["o": Color(hex: "#3A2E4F"), "b": Color(hex: "#FFF4E0"),
                    "s": species == .rabbit ? Color(hex: "#FF9EC4") : spot]
        }
        var result: [Character: Color] = [:]
        for (key, hex) in species.sheet.palette { result[key] = Color(hex: hex) }
        return result
    }

    private func composeGrid() -> [[Character]] {
        if stage == .egg { return PetSprites.egg.map(Array.init) }
        let sheet = species.sheet
        var grid = sheet.body.map(Array.init)
        func set(_ r: Int, _ c: Int, _ code: Character) {
            guard r >= 0, r < 20, c >= 0, c < 20 else { return }
            grid[r][c] = code
        }
        for eye in sheet.eyes {
            switch expression {
            case .sleep, .blink:
                set(eye.row + 1, eye.col, "o"); set(eye.row + 1, eye.col + 1, "o")
            case .happy:
                set(eye.row, eye.col, "o"); set(eye.row, eye.col + 1, "o")
                set(eye.row + 1, eye.col - 1, "o"); set(eye.row + 1, eye.col + 2, "o")
            case .normal, .eat:
                set(eye.row, eye.col, "o"); set(eye.row + 1, eye.col, "o")
                set(eye.row, eye.col + 1, "o"); set(eye.row + 1, eye.col + 1, "o")
            }
        }
        let mouth = sheet.mouth
        set(mouth.row, mouth.col, "o"); set(mouth.row, mouth.col + 1, "o")
        if expression == .eat {
            set(mouth.row + 1, mouth.col, "p"); set(mouth.row + 1, mouth.col + 1, "p")
        }
        for cheek in sheet.cheeks {
            set(cheek.row, cheek.col, "p"); set(cheek.row, cheek.col + 1, "p")
        }
        for foot in stepB ? sheet.feetB : sheet.feetA {
            for c in foot.from...foot.to { set(foot.row, c, "o") }
        }
        if stage == .adult {
            for paint in sheet.accessory { set(paint.row, paint.col, paint.code) }
        }
        return grid
    }
}

// MARK: - Live, animated pet

/// The animated pet: idles, blinks, walks, eats coins, sleeps, worries and cheers.
struct LivePet: View {
    var size: CGFloat = 56
    /// Walk back and forth across the available width.
    var roams = false
    var interactive = true
    /// Force an expression (e.g. the entry sheet reacting to the amount).
    var forced: PetExpression? = nil

    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    var body: some View {
        let center = PetCenter.shared
        if settings.petEnabled {
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1.0 / 8, paused: !visible || scenePhase != .active)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    frame(center: center, t: t, width: geo.size.width, now: timeline.date)
                }
            }
            .frame(height: size + (interactive ? 34 : 0))
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(center.status.name)，\(center.status.stage.title)，\(center.status.mood.title)")
            .accessibilityAddTraits(interactive ? .isButton : [])
            .accessibilityAction { if interactive { center.poke() } }
        }
    }

    private struct FrameState {
        var eating = false, cheering = false, hopping = false, sleeping = false, walking = false, flipped = false
        var x: CGFloat = 0, lift: CGFloat = 0, wobble: Double = 0
        var tick = 0
        var expression: PetExpression = .normal
    }

    /// Pure animation math for one frame (kept out of the view builder).
    private func frameState(center: PetCenter, t: TimeInterval, width: CGFloat, now: Date) -> FrameState {
        let status = center.status
        var f = FrameState()
        f.eating = now < center.eatUntil
        f.cheering = now < center.cheerUntil
        f.hopping = now < center.hopUntil
        f.sleeping = status.mood == .sleepy && !f.eating && !f.cheering && status.stage != .egg

        // Walking: a slow ping-pong across the width, pausing at each end.
        let travel = max(0, width - size)
        let phase = t.truncatingRemainder(dividingBy: 14) / 14
        f.walking = roams && !f.sleeping && !f.eating && status.stage != .egg
            && (phase < 0.4 || (phase > 0.5 && phase < 0.9))
        let progress: Double
        if phase < 0.4 { progress = phase / 0.4 }
        else if phase < 0.5 { progress = 1 }
        else if phase < 0.9 { progress = 1 - (phase - 0.5) / 0.4 }
        else { progress = 0 }
        f.x = roams ? travel * progress : (width - size) / 2
        f.flipped = roams && phase >= 0.45 && phase < 0.95

        f.tick = Int(t * 8)
        if let forced { f.expression = forced }
        else if f.sleeping { f.expression = .sleep }
        else if f.eating { f.expression = f.tick % 4 < 2 ? .eat : .happy }
        else if f.cheering || (status.mood == .happy && f.tick % 40 < 6) { f.expression = .happy }
        else if f.tick % 30 == 0 { f.expression = .blink }

        if f.cheering || f.hopping {
            let p = (t * 3).truncatingRemainder(dividingBy: 1)
            f.lift = CGFloat(sin(p * .pi)) * size * 0.35
        } else if f.walking {
            f.lift = f.tick % 2 == 0 ? size * 0.04 : 0
        } else if !f.sleeping {
            f.lift = f.tick % 8 < 4 ? size * 0.025 : 0
        }
        if status.stage == .egg {
            f.wobble = f.tick % 16 < 2 ? 6 : (f.tick % 16 < 4 ? -6 : 0)
        }
        return f
    }

    @ViewBuilder
    private func frame(center: PetCenter, t: TimeInterval, width: CGFloat, now: Date) -> some View {
        let status = center.status
        let f = frameState(center: center, t: t, width: width, now: now)

        ZStack(alignment: .bottomLeading) {
            Color.clear
            ZStack(alignment: .bottom) {
                // Shadow
                Ellipse()
                    .fill(.black.opacity(0.15))
                    .frame(width: size * 0.6, height: size * 0.08)
                    .offset(y: size * 0.02)
                PetSpriteView(species: status.species, stage: status.stage, expression: f.expression,
                              stepB: f.walking && f.tick % 2 == 0, flipped: f.flipped)
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(f.wobble), anchor: .bottom)
                    .offset(y: -f.lift)
                effects(status: status, eating: f.eating, cheering: f.cheering, sleeping: f.sleeping, t: t)
            }
            .frame(width: size, height: size)
            .overlay(alignment: .top) {
                if interactive, let speech = center.speech {
                    SpeechBubble(text: speech)
                        .fixedSize()
                        .offset(y: -30)
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                }
            }
            .offset(x: f.x)
            .contentShape(Rectangle())
            .onTapGesture { if interactive { center.poke() } }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    /// Pixel particles: falling coin while eating, Zs while asleep, sweat when worried, sparkles when cheering.
    @ViewBuilder
    private func effects(status: PetStatus, eating: Bool, cheering: Bool, sleeping: Bool, t: TimeInterval) -> some View {
        let px = size / 20
        if eating {
            let fall = (t * 1.6).truncatingRemainder(dividingBy: 1)
            PixelCoin(px: px)
                .offset(y: -size * 0.95 + CGFloat(fall) * size * 0.45)
                .opacity(1 - fall * 0.6)
        }
        if sleeping {
            let rise = (t * 0.5).truncatingRemainder(dividingBy: 1)
            Text("z")
                .font(.system(size: px * 5, weight: .black, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.4), radius: 0, x: 1, y: 1)
                .offset(x: size * 0.35 + CGFloat(rise) * px * 3, y: -size * 0.7 - CGFloat(rise) * size * 0.3)
                .opacity(1 - rise)
        }
        if status.mood == .worried && !sleeping && !eating && !cheering {
            Rectangle()
                .fill(Color(hex: "#7FD3FF"))
                .frame(width: px * 1.6, height: px * 2.4)
                .offset(x: size * 0.36, y: -size * 0.62 + CGFloat(Int(t * 2) % 2) * px)
        }
        if cheering {
            ForEach(0..<6, id: \.self) { index in
                let angle = Double(index) / 6 * 2 * .pi + t * 2
                Rectangle()
                    .fill(index.isMultiple(of: 2) ? Color(hex: "#FFD84A") : Color(hex: "#FF9EC4"))
                    .frame(width: px * 1.5, height: px * 1.5)
                    .offset(x: CGFloat(cos(angle)) * size * 0.55, y: -size * 0.55 + CGFloat(sin(angle)) * size * 0.45)
            }
        }
    }
}

private struct PixelCoin: View {
    let px: CGFloat
    var body: some View {
        ZStack {
            Rectangle().fill(Color(hex: "#C98A1A")).frame(width: px * 4, height: px * 4)
            Rectangle().fill(Color(hex: "#FFD84A")).frame(width: px * 2.6, height: px * 2.6)
            Rectangle().fill(Color(hex: "#C98A1A")).frame(width: px * 0.8, height: px * 1.6)
        }
    }
}

/// Pixel speech bubble.
struct SpeechBubble: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = PixelPalette(scheme: scheme)
        Text(text)
            .font(Font.skin(.caption))
            .foregroundStyle(Color.primary)
            .lineLimit(2)
            .frame(maxWidth: 220)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                ZStack {
                    PixelRect(step: 3).fill(palette.panel)
                    PixelRect(step: 3).stroke(palette.border, lineWidth: 2)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.border).frame(width: 6, height: 6).offset(y: 5)
            }
    }
}

/// The row on the home screen where the pet strolls above the month card.
struct PetPerch: View {
    @Environment(Router.self) private var router

    var body: some View {
        LivePet(size: 52, roams: true)
            .padding(.horizontal, 8)
            .contextMenu {
                Button("看看\(PetCenter.shared.status.name)", systemImage: "pawprint.fill") {
                    router.homeRoute = .pet
                }
            }
    }
}
