import SwiftUI

/// Draws a stored 20×20 custom pet. `scale` follows the built-in growth stages.
struct PetRasterView: View {
    var raster: PetRaster
    var scale: CGFloat = 1
    var centered = false

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let cell = floor(min(size.width, size.height) / CGFloat(PetRaster.side) * scale * 2) / 2
            guard cell > 0 else { return }
            let total = cell * CGFloat(PetRaster.side)
            let originX = (size.width - total) / 2
            let originY = centered ? (size.height - total) / 2 : size.height - total
            for y in 0..<PetRaster.side {
                for x in 0..<PetRaster.side {
                    let pixel = raster.pixel(x: x, y: y)
                    guard pixel.a >= 16 else { continue }
                    let rect = CGRect(x: originX + CGFloat(x) * cell, y: originY + CGFloat(y) * cell, width: cell + 0.5, height: cell + 0.5)
                    let color = Color(
                        red: Double(pixel.r) / 255,
                        green: Double(pixel.g) / 255,
                        blue: Double(pixel.b) / 255,
                        opacity: Double(pixel.a) / 255
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
