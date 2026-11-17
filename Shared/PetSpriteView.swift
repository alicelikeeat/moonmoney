import SwiftUI

/// Draws one frame of a pet on a 20×20 pixel grid. Shared by the app, widgets, and Live Activity.
struct PetSpriteView: View {
    let species: PetSpecies
    let stage: PetStage
    var expression: PetExpression = .normal
    var stepB = false
    var flipped = false
    /// In-app pets stand on the bottom edge. Widgets and the island center the sprite in the frame.
    var centered = false

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let grid = composeGrid()
            let palette = paletteColors()
            let cell = floor(min(size.width, size.height) / 20 * stage.scale * 2) / 2
            let total = cell * 20
            let originX = (size.width - total) / 2
            let originY = centered ? (size.height - total) / 2 : size.height - total
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
