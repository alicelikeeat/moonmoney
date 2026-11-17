import CoreGraphics
import Foundation
import Testing
@testable import MoonMoney

struct PetPixelateTests {
    private func color(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) -> PetPixelColor {
        PetPixelColor(r: r, g: g, b: b, a: a)
    }

    private func bitmap(width: Int, height: Int, _ fill: (Int, Int) -> PetPixelColor) -> PetBitmap {
        var pixels: [PetPixelColor] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width { pixels.append(fill(x, y)) }
        }
        return PetBitmap(width: width, height: height, pixels: pixels)
    }

    private func solidImage(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> CGImage {
        let width = 4
        let height = 4
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) {
            bytes[index * 4] = r
            bytes[index * 4 + 1] = g
            bytes[index * 4 + 2] = b
            bytes[index * 4 + 3] = 255
        }
        let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    @Test func downsampleKeepsASplitOfTwoColors() {
        let source = bitmap(width: 20, height: 20) { x, _ in
            x < 10 ? color(220, 40, 40) : color(40, 80, 220)
        }
        let raster = PetPixelate.rasters(from: [source], paletteCount: 4, cropInset: 0).first
        let result = try! #require(raster)
        let left = result.pixel(x: 2, y: 10)
        let right = result.pixel(x: 17, y: 10)
        #expect(left.r > left.b)
        #expect(right.b > right.r)
        let unique = Set(result.pixels.filter(\.isOpaque).map { "\($0.r),\($0.g),\($0.b)" })
        #expect(unique.count <= 4)
        #expect(unique.count >= 2)
    }

    @Test func cropInsetDropsTheBorder() {
        let source = bitmap(width: 20, height: 20) { x, y in
            x == 0 || y == 0 || x == 19 || y == 19 ? color(200, 0, 0) : color(0, 0, 200)
        }
        let loose = try! #require(PetPixelate.rasters(from: [source], paletteCount: 4, cropInset: 0).first)
        let tight = try! #require(PetPixelate.rasters(from: [source], paletteCount: 4, cropInset: 0.2).first)
        #expect(loose.pixels.contains { $0.isOpaque && $0.r > $0.b })
        #expect(!tight.pixels.contains { $0.isOpaque && $0.r > 80 })
    }

    @Test func paletteSizeIsACeiling() {
        let source = bitmap(width: 20, height: 20) { x, _ in
            color(UInt8(x * 12), 40, 40)
        }
        let raster = try! #require(PetPixelate.rasters(from: [source], paletteCount: 4, cropInset: 0).first)
        let unique = Set(raster.pixels.filter(\.isOpaque).map { "\($0.r),\($0.g),\($0.b)" })
        #expect(unique.count <= 4)
        #expect(unique.count >= 2)
    }

    @Test func emptyBitmapProducesNothing() {
        let source = bitmap(width: 8, height: 8) { _, _ in .clear }
        #expect(PetPixelate.rasters(from: [source], paletteCount: 6, cropInset: 0).isEmpty)
        #expect(PetPixelate.opaqueBounds(source) == nil)
    }

    @Test func sharedPaletteKeepsAnimationFramesConsistent() {
        let red = bitmap(width: 10, height: 10) { _, _ in color(200, 20, 20) }
        let blue = bitmap(width: 10, height: 10) { _, _ in color(20, 40, 200) }
        let frames = PetPixelate.rasters(from: [red, blue], paletteCount: 2, cropInset: 0)
        #expect(frames.count == 2)
        let colors = Set(frames.flatMap(\.pixels).filter(\.isOpaque).map { "\($0.r),\($0.g),\($0.b)" })
        #expect(colors.count == 2)
        #expect(frames[0].pixel(x: 5, y: 5).r > frames[1].pixel(x: 5, y: 5).r)
    }

    @Test func moodAndStageVariantsFollowTheBuiltInRules() {
        let source = bitmap(width: 16, height: 16) { _, _ in color(180, 120, 60) }
        let base = try! #require(PetPixelate.rasters(from: [source], paletteCount: 4, cropInset: 0).first)
        let happy = PetPixelate.styled(base, mood: .happy, stage: .teen)
        let sleepy = PetPixelate.styled(base, mood: .sleepy, stage: .teen)
        let worried = PetPixelate.styled(base, mood: .worried, stage: .teen)
        let adult = PetPixelate.styled(base, mood: .normal, stage: .adult)
        #expect(meanLuminance(happy) > meanLuminance(base))
        #expect(meanLuminance(sleepy) < meanLuminance(base))
        #expect(meanChannel(worried, \.b) > meanChannel(base, \.b))
        #expect(adult != base)
        #expect(adult.pixel(x: 9, y: 0).r > 200)

        let egg = PetPixelate.styled(base, mood: .happy, stage: .egg)
        let emptyCells = PetSprites.egg.joined().filter { $0 == "." }.count
        #expect(egg.pixels.filter { !$0.isOpaque }.count == emptyCells)
        #expect(!egg.pixel(x: 0, y: 0).isOpaque)
    }

    @Test func frameIndexesIncludeBothEnds() {
        #expect(PetFramePicker.indices(frameCount: 0) == [])
        #expect(PetFramePicker.indices(frameCount: 3, limit: 8) == [0, 1, 2])
        let picked = PetFramePicker.indices(frameCount: 16, limit: 8)
        #expect(picked.count == 8)
        #expect(picked.first == 0)
        #expect(picked.last == 15)
        #expect(picked == picked.sorted())
        #expect(Set(picked).count == picked.count)
    }

    @Test func videoTimestampsStayInsideTheClip() {
        let times = PetFramePicker.timestamps(duration: 10, limit: 4)
        #expect(times.count == 4)
        #expect(times == times.sorted())
        #expect(times.allSatisfy { $0 >= 0 && $0 < 10 })
        #expect(PetFramePicker.timestamps(duration: 0, limit: 4).isEmpty)
    }

    @Test func gifRoundTripKeepsBothFrames() throws {
        let data = try #require(PetFrameExtractor.makeGIF([solidImage(240, 30, 30), solidImage(30, 40, 220)]))
        #expect(PetFrameExtractor.isGIF(data))
        #expect(PetFrameExtractor.frameCount(data: data) == 2)
        let images = PetFrameExtractor.gifImages(data: data, limit: 8)
        #expect(images.count == 2)
        let first = PetImporter.bitmap(from: images[0]).pixel(x: 0, y: 0)
        let second = PetImporter.bitmap(from: images[1]).pixel(x: 0, y: 0)
        #expect(first.r > first.b)
        #expect(second.b > second.r)
    }

    @Test func customPetRoundTripUsesTheAppGroupFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pet-custom-\(UUID().uuidString)", isDirectory: true)
        PetCustomLibrary.directoryOverride = folder
        defer {
            PetCustomLibrary.directoryOverride = nil
            try? FileManager.default.removeItem(at: folder)
        }
        let source = bitmap(width: 8, height: 8) { _, _ in color(10, 200, 80) }
        let raster = try #require(PetPixelate.rasters(from: [source], paletteCount: 4, cropInset: 0).first)
        let record = PetCustomRecord(id: "abc", name: "豆豆", frames: [raster], createdAt: .now)
        PetCustomLibrary.save(record)
        let loaded = try #require(PetCustomLibrary.record(id: "abc"))
        #expect(loaded.name == "豆豆")
        #expect(loaded.frames.count == 1)
        let shown = try #require(PetCustomLibrary.frame(id: "abc", index: 0, mood: .normal, stage: .baby))
        #expect(shown.pixel(x: 10, y: 10).g > shown.pixel(x: 10, y: 10).r)
        PetCustomLibrary.delete(id: "abc")
        #expect(PetCustomLibrary.record(id: "abc") == nil)
    }

    private func meanLuminance(_ raster: PetRaster) -> Int {
        let opaque = raster.pixels.filter(\.isOpaque)
        guard !opaque.isEmpty else { return 0 }
        return opaque.reduce(0) { $0 + $1.luminance } / opaque.count
    }

    private func meanChannel(_ raster: PetRaster, _ key: KeyPath<PetPixelColor, UInt8>) -> Int {
        let opaque = raster.pixels.filter(\.isOpaque)
        guard !opaque.isEmpty else { return 0 }
        return opaque.reduce(0) { $0 + Int($1[keyPath: key]) } / opaque.count
    }
}
