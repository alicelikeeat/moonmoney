import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Pixels

struct PetPixelColor: Equatable, Hashable, Codable, Sendable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    static let clear = PetPixelColor(r: 0, g: 0, b: 0, a: 0)

    var isOpaque: Bool { a >= 128 }

    var luminance: Int { (Int(r) * 3 + Int(g) * 4 + Int(b)) / 8 }
}

struct PetBitmap: Equatable, Sendable {
    var width: Int
    var height: Int
    var pixels: [PetPixelColor]

    func pixel(x: Int, y: Int) -> PetPixelColor {
        guard x >= 0, y >= 0, x < width, y < height else { return .clear }
        return pixels[y * width + x]
    }
}

/// A 20×20 pixel-art frame. Transparent cells stay clear so the subject keeps its outline.
struct PetRaster: Equatable, Codable, Sendable {
    static let side = 20
    var pixels: [PetPixelColor]

    init(pixels: [PetPixelColor]) {
        if pixels.count == Self.side * Self.side {
            self.pixels = pixels
        } else {
            var padded = pixels.prefix(Self.side * Self.side)
            if padded.count < Self.side * Self.side {
                padded += Array(repeating: .clear, count: Self.side * Self.side - padded.count)
            }
            self.pixels = Array(padded)
        }
    }

    func pixel(x: Int, y: Int) -> PetPixelColor {
        guard x >= 0, y >= 0, x < Self.side, y < Self.side else { return .clear }
        return pixels[y * Self.side + x]
    }
}

struct PetCustomRecord: Equatable, Codable, Sendable {
    var id: String
    var name: String
    var frames: [PetRaster]
    var createdAt: Date
}

// MARK: - Frame picking

enum PetFramePicker {
    /// Enough for an idle loop, small enough to store in the App Group and to run through Vision.
    static let maxFrames = 8

    /// Evenly spaced indexes, always including the first and last frame when there is more than one.
    static func indices(frameCount: Int, limit: Int = maxFrames) -> [Int] {
        guard frameCount > 0, limit > 0 else { return [] }
        if frameCount <= limit { return Array(0..<frameCount) }
        if limit == 1 { return [0] }
        return (0..<limit).map { step in
            Int((Double(step) * Double(frameCount - 1) / Double(limit - 1)).rounded())
        }
    }

    /// Sample times inside a video, never quite at the end (some files have no frame there).
    static func timestamps(duration: Double, limit: Int = maxFrames) -> [Double] {
        guard duration > 0, limit > 0 else { return [] }
        if limit == 1 { return [min(duration * 0.5, max(0, duration - 0.05))] }
        let last = max(0, duration - 0.05)
        return (0..<limit).map { step in
            min(last, Double(step) * duration / Double(limit))
        }
    }
}

// MARK: - Pixelation

enum PetPixelate {
    struct Bounds {
        var minX: Int
        var minY: Int
        var maxX: Int
        var maxY: Int
    }

    /// Downsamples each bitmap to 20×20 and maps every frame onto one shared palette.
    static func rasters(from bitmaps: [PetBitmap], paletteCount: Int, cropInset: Double) -> [PetRaster] {
        let sampled = bitmaps.compactMap { sample($0, cropInset: cropInset) }
        let opaque = sampled.flatMap { $0.filter(\.isOpaque) }
        let palette = medianCut(opaque, count: min(16, max(2, paletteCount)))
        guard !palette.isEmpty else { return [] }
        return sampled.map { cells in
            PetRaster(pixels: cells.map { cell in
                cell.isOpaque ? nearest(cell, palette: palette) : .clear
            })
        }
    }

    /// Mood and growth treatment on top of a saved frame. The egg uses the built-in silhouette, tinted with this pet's colors.
    static func styled(_ raster: PetRaster, mood: PetMood, stage: PetStage) -> PetRaster {
        if stage == .egg { return egg(from: raster) }
        var next = raster
        switch mood {
        case .happy: next = map(next, brighten)
        case .sleepy: next = stamp(map(next, darken), sleepyMark)
        case .worried: next = stamp(map(next, cool), worryMark)
        case .hungry: next = map(next, desaturate)
        case .normal: break
        }
        if stage == .adult { next = stamp(next, star) }
        return next
    }

    static func egg(from raster: PetRaster) -> PetRaster {
        let common = mostCommon(raster, limit: 2)
        let fill = common.first ?? PetPixelColor(r: 255, g: 244, b: 224, a: 255)
        let spot = common.dropFirst().first ?? fill
        let outline = PetPixelColor(r: 58, g: 46, b: 79, a: 255)
        var pixels = [PetPixelColor](repeating: .clear, count: PetRaster.side * PetRaster.side)
        for (y, line) in PetSprites.egg.enumerated() {
            for (x, code) in line.enumerated() where x < PetRaster.side {
                let color: PetPixelColor = switch code {
                case "o": outline
                case "s": spot
                case "b": fill
                default: .clear
                }
                pixels[y * PetRaster.side + x] = color
            }
        }
        return PetRaster(pixels: pixels)
    }

    static func opaqueBounds(_ bitmap: PetBitmap) -> Bounds? {
        var bounds: Bounds?
        guard bitmap.width > 0, bitmap.height > 0, bitmap.pixels.count >= bitmap.width * bitmap.height else { return nil }
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where bitmap.pixel(x: x, y: y).isOpaque {
                if var current = bounds {
                    current.minX = min(current.minX, x)
                    current.minY = min(current.minY, y)
                    current.maxX = max(current.maxX, x + 1)
                    current.maxY = max(current.maxY, y + 1)
                    bounds = current
                } else {
                    bounds = Bounds(minX: x, minY: y, maxX: x + 1, maxY: y + 1)
                }
            }
        }
        return bounds
    }

    static func inset(_ bounds: Bounds, fraction: Double) -> Bounds {
        let fraction = min(max(fraction, 0), 0.45)
        let dx = Int((Double(bounds.maxX - bounds.minX) * fraction).rounded(.down))
        let dy = Int((Double(bounds.maxY - bounds.minY) * fraction).rounded(.down))
        let next = Bounds(minX: bounds.minX + dx, minY: bounds.minY + dy, maxX: bounds.maxX - dx, maxY: bounds.maxY - dy)
        guard next.maxX - next.minX >= 1, next.maxY - next.minY >= 1 else { return bounds }
        return next
    }

    static func medianCut(_ colors: [PetPixelColor], count: Int) -> [PetPixelColor] {
        let opaque = colors.filter(\.isOpaque)
        guard !opaque.isEmpty, count > 0 else { return [] }
        if opaque.count <= count { return unique(opaque) }
        var boxes: [[PetPixelColor]] = [opaque]
        while boxes.count < count {
            guard let index = boxes.indices.max(by: { channelSpan($0, in: boxes) < channelSpan($1, in: boxes) }),
                  channelSpan(index, in: boxes).span > 0,
                  let parts = split(boxes[index], channel: channelSpan(index, in: boxes).channel) else { break }
            boxes.remove(at: index)
            boxes.append(contentsOf: parts)
        }
        return boxes.map(average)
    }

    // MARK: Sampling

    private static func sample(_ bitmap: PetBitmap, cropInset: Double) -> [PetPixelColor]? {
        guard let bounds = opaqueBounds(bitmap) else { return nil }
        let box = inset(bounds, fraction: cropInset)
        let width = Double(box.maxX - box.minX)
        let height = Double(box.maxY - box.minY)
        var cells: [PetPixelColor] = []
        cells.reserveCapacity(PetRaster.side * PetRaster.side)
        for row in 0..<PetRaster.side {
            for col in 0..<PetRaster.side {
                let x0 = Double(box.minX) + width * Double(col) / Double(PetRaster.side)
                let x1 = Double(box.minX) + width * Double(col + 1) / Double(PetRaster.side)
                let y0 = Double(box.minY) + height * Double(row) / Double(PetRaster.side)
                let y1 = Double(box.minY) + height * Double(row + 1) / Double(PetRaster.side)
                cells.append(average(in: bitmap, x0: x0, x1: x1, y0: y0, y1: y1))
            }
        }
        return cells.contains(where: \.isOpaque) ? cells : nil
    }

    private static func average(in bitmap: PetBitmap, x0: Double, x1: Double, y0: Double, y1: Double) -> PetPixelColor {
        let left = max(0, Int(x0.rounded(.down)))
        let right = min(bitmap.width, max(left + 1, Int(x1.rounded(.up))))
        let top = max(0, Int(y0.rounded(.down)))
        let bottom = min(bitmap.height, max(top + 1, Int(y1.rounded(.up))))
        var colors: [PetPixelColor] = []
        for y in top..<bottom {
            for x in left..<right {
                let pixel = bitmap.pixel(x: x, y: y)
                if pixel.isOpaque { colors.append(pixel) }
            }
        }
        guard !colors.isEmpty else { return .clear }
        var averaged = average(colors)
        averaged.a = 255
        return averaged
    }

    private static func channelSpan(_ index: Int, in boxes: [[PetPixelColor]]) -> (channel: Int, span: Int) {
        var minC = [255, 255, 255]
        var maxC = [0, 0, 0]
        for color in boxes[index] where color.isOpaque {
            let channels = [Int(color.r), Int(color.g), Int(color.b)]
            for i in 0..<3 {
                minC[i] = min(minC[i], channels[i])
                maxC[i] = max(maxC[i], channels[i])
            }
        }
        var best = (channel: 0, span: maxC[0] - minC[0])
        for i in 1..<3 {
            let span = maxC[i] - minC[i]
            if span > best.span { best = (i, span) }
        }
        return best
    }

    private static func split(_ colors: [PetPixelColor], channel: Int) -> [[PetPixelColor]]? {
        let sorted = colors.sorted { component($0, channel) < component($1, channel) }
        let mid = sorted.count / 2
        guard mid > 0, mid < sorted.count else { return nil }
        return [Array(sorted[..<mid]), Array(sorted[mid...])]
    }

    private static func component(_ color: PetPixelColor, _ channel: Int) -> Int {
        switch channel {
        case 0: Int(color.r)
        case 1: Int(color.g)
        default: Int(color.b)
        }
    }

    private static func unique(_ colors: [PetPixelColor]) -> [PetPixelColor] {
        var seen: [PetPixelColor] = []
        for color in colors where color.isOpaque && !seen.contains(where: { $0.r == color.r && $0.g == color.g && $0.b == color.b }) {
            var solid = color
            solid.a = 255
            seen.append(solid)
        }
        return seen
    }

    private static func average(_ colors: [PetPixelColor]) -> PetPixelColor {
        let source = colors.filter(\.isOpaque)
        let used = source.isEmpty ? colors : source
        guard !used.isEmpty else { return .clear }
        let count = used.count
        let r = used.reduce(0) { $0 + Int($1.r) } / count
        let g = used.reduce(0) { $0 + Int($1.g) } / count
        let b = used.reduce(0) { $0 + Int($1.b) } / count
        return PetPixelColor(r: UInt8(r), g: UInt8(g), b: UInt8(b), a: 255)
    }

    private static func nearest(_ color: PetPixelColor, palette: [PetPixelColor]) -> PetPixelColor {
        guard var best = palette.first else { return color }
        var bestDistance = distance(color, best)
        for candidate in palette.dropFirst() {
            let value = distance(color, candidate)
            if value < bestDistance {
                best = candidate
                bestDistance = value
            }
        }
        best.a = 255
        return best
    }

    private static func distance(_ lhs: PetPixelColor, _ rhs: PetPixelColor) -> Int {
        let dr = Int(lhs.r) - Int(rhs.r)
        let dg = Int(lhs.g) - Int(rhs.g)
        let db = Int(lhs.b) - Int(rhs.b)
        return dr * dr + dg * dg + db * db
    }

    private static func mostCommon(_ raster: PetRaster, limit: Int) -> [PetPixelColor] {
        var counts: [PetPixelColor: Int] = [:]
        for pixel in raster.pixels where pixel.isOpaque {
            let key = PetPixelColor(r: pixel.r, g: pixel.g, b: pixel.b, a: 255)
            counts[key, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
    }

    private static func map(_ raster: PetRaster, _ transform: (PetPixelColor) -> PetPixelColor) -> PetRaster {
        PetRaster(pixels: raster.pixels.map { pixel in
            pixel.isOpaque ? transform(pixel) : .clear
        })
    }

    private static func brighten(_ color: PetPixelColor) -> PetPixelColor {
        func lift(_ value: UInt8) -> UInt8 { UInt8(min(255, Int(value) + (255 - Int(value)) / 5 + 8)) }
        return PetPixelColor(r: lift(color.r), g: lift(color.g), b: lift(color.b), a: 255)
    }

    private static func darken(_ color: PetPixelColor) -> PetPixelColor {
        func drop(_ value: UInt8) -> UInt8 { UInt8(Int(value) * 6 / 10) }
        return PetPixelColor(r: drop(color.r), g: drop(color.g), b: drop(color.b), a: 255)
    }

    private static func desaturate(_ color: PetPixelColor) -> PetPixelColor {
        let gray = color.luminance
        func mix(_ value: UInt8) -> UInt8 { UInt8((Int(value) + gray) / 2) }
        return PetPixelColor(r: mix(color.r), g: mix(color.g), b: mix(color.b), a: 255)
    }

    private static func cool(_ color: PetPixelColor) -> PetPixelColor {
        PetPixelColor(
            r: UInt8(Int(color.r) * 7 / 10),
            g: UInt8(Int(color.g) * 8 / 10),
            b: UInt8(min(255, Int(color.b) + 36)),
            a: 255
        )
    }

    private static let star: [(Int, Int, PetPixelColor)] = {
        let gold = PetPixelColor(r: 255, g: 210, b: 74, a: 255)
        return [(9, 0, gold), (8, 1, gold), (9, 1, gold), (10, 1, gold), (9, 2, gold)]
    }()

    private static let worryMark: [(Int, Int, PetPixelColor)] = {
        let drop = PetPixelColor(r: 127, g: 211, b: 255, a: 255)
        return [(17, 3, drop), (17, 4, drop), (18, 5, drop)]
    }()

    private static let sleepyMark: [(Int, Int, PetPixelColor)] = {
        let ink = PetPixelColor(r: 255, g: 244, b: 224, a: 255)
        return [(15, 1, ink), (16, 1, ink), (15, 2, ink), (16, 3, ink)]
    }()

    private static func stamp(_ raster: PetRaster, _ marks: [(Int, Int, PetPixelColor)]) -> PetRaster {
        var pixels = raster.pixels
        for (x, y, color) in marks where x >= 0 && y >= 0 && x < PetRaster.side && y < PetRaster.side {
            pixels[y * PetRaster.side + x] = color
        }
        return PetRaster(pixels: pixels)
    }
}

// MARK: - GIF frames

enum PetFrameExtractor {
    static func isGIF(_ data: Data) -> Bool {
        data.starts(with: Data("GIF8".utf8))
    }

    static func frameCount(data: Data) -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return 0 }
        return CGImageSourceGetCount(source)
    }

    static func image(data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func gifImages(data: Data, limit: Int = PetFramePicker.maxFrames) -> [CGImage] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        let count = CGImageSourceGetCount(source)
        return PetFramePicker.indices(frameCount: count, limit: limit).compactMap { index in
            CGImageSourceCreateImageAtIndex(source, index, nil)
        }
    }

    /// Writes a GIF so tests (and nothing else) can round-trip frame picking without a fixture file.
    static func makeGIF(_ images: [CGImage]) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, images.count, nil) else { return nil }
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary
        for image in images {
            CGImageDestinationAddImage(destination, image, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

// MARK: - App Group storage

enum PetCustomLibrary {
    private struct CacheEntry {
        var modified: Date
        var record: PetCustomRecord
    }

    nonisolated(unsafe) private static var cache: [String: CacheEntry] = [:]
    nonisolated(unsafe) static var directoryOverride: URL?

    static func frame(id: String?, index: Int, mood: PetMood, stage: PetStage) -> PetRaster? {
        guard let id, !id.isEmpty, let record = record(id: id), !record.frames.isEmpty else { return nil }
        let frame = record.frames[abs(index) % record.frames.count]
        return PetPixelate.styled(frame, mood: mood, stage: stage)
    }

    static func frameCount(id: String?) -> Int {
        guard let id, !id.isEmpty else { return 0 }
        return record(id: id)?.frames.count ?? 0
    }

    static func all() -> [PetCustomRecord] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap { record(at: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func save(_ record: PetCustomRecord) {
        let url = file(id: record.id)
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: url, options: .atomic)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
        cache[record.id] = CacheEntry(modified: modified, record: record)
    }

    static func delete(id: String) {
        cache[id] = nil
        try? FileManager.default.removeItem(at: file(id: id))
    }

    static func record(id: String) -> PetCustomRecord? {
        let url = file(id: id)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        if let hit = cache[id], hit.modified == modified { return hit.record }
        guard let loaded = record(at: url) else { return nil }
        cache[id] = CacheEntry(modified: modified, record: loaded)
        return loaded
    }

    private static func record(at url: URL) -> PetCustomRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PetCustomRecord.self, from: data)
    }

    private static var directory: URL {
        if let directoryOverride {
            try? FileManager.default.createDirectory(at: directoryOverride, withIntermediateDirectories: true)
            return directoryOverride
        }
        let base = AppGroup.containerURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent("CustomPets", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func file(id: String) -> URL {
        let safe = id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return directory.appendingPathComponent(safe.isEmpty ? "pet" : safe).appendingPathExtension("json")
    }
}
