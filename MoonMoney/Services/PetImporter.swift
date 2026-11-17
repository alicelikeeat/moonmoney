import AVFoundation
import CoreImage
import Foundation
import PhotosUI
import SwiftUI
import Vision

enum PetImportError: LocalizedError, Equatable {
    case unreadable
    case noSubject
    case noFrames

    var errorDescription: String? {
        switch self {
        case .unreadable: "这份照片或视频打不开。"
        case .noSubject: "没有找到清晰的主体。换一张主体更突出的照片，或者改用整张图片。"
        case .noFrames: "没有从这段视频里取出画面。"
        }
    }
}

struct PickedPetSource: Transferable {
    var data: Data?
    var fileURL: URL?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { source in
            SentTransferredFile(source.fileURL ?? URL(fileURLWithPath: "/dev/null"))
        } importing: { received in
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedPetSource(data: nil, fileURL: destination)
        }
        DataRepresentation(importedContentType: .image) { data in
            PickedPetSource(data: data, fileURL: nil)
        }
    }
}

/// Turns a photo, GIF, or video into masked bitmaps on device. Pixelation itself lives in `PetPixelate`.
enum PetImporter {
    static func bitmaps(from source: PickedPetSource, cutout: Bool) async throws -> [PetBitmap] {
        if let url = source.fileURL {
            return try await videoBitmaps(url: url, cutout: cutout)
        }
        guard let data = source.data else { throw PetImportError.unreadable }
        if PetFrameExtractor.frameCount(data: data) > 1 {
            let images = PetFrameExtractor.gifImages(data: data)
            return try collect(images, cutout: cutout)
        }
        guard let image = PetFrameExtractor.image(data: data) else { throw PetImportError.unreadable }
        return try collect([image], cutout: cutout)
    }

    static func bitmap(from image: CGImage) -> PetBitmap {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var pixels: [PetPixelColor] = []
        pixels.reserveCapacity(width * height)
        for index in 0..<(width * height) {
            let offset = index * 4
            let alpha = Int(bytes[offset + 3])
            if alpha == 0 {
                pixels.append(.clear)
                continue
            }
            let scale = alpha == 255 ? 1 : 255 / max(alpha, 1)
            pixels.append(PetPixelColor(
                r: UInt8(min(255, Int(bytes[offset]) * scale)),
                g: UInt8(min(255, Int(bytes[offset + 1]) * scale)),
                b: UInt8(min(255, Int(bytes[offset + 2]) * scale)),
                a: UInt8(alpha)
            ))
        }
        return PetBitmap(width: width, height: height, pixels: pixels)
    }

    private static func collect(_ images: [CGImage], cutout: Bool) throws -> [PetBitmap] {
        var bitmaps: [PetBitmap] = []
        var missedSubject = false
        for image in images {
            do {
                bitmaps.append(try prepare(image, cutout: cutout))
            } catch PetImportError.noSubject {
                missedSubject = true
            } catch {
                continue
            }
        }
        if bitmaps.isEmpty { throw missedSubject ? PetImportError.noSubject : PetImportError.noFrames }
        return bitmaps
    }

    private static func prepare(_ image: CGImage, cutout: Bool) throws -> PetBitmap {
        let fitted = downscaled(image, maxSide: 160)
        if !cutout {
            var bitmap = bitmap(from: fitted)
            for index in bitmap.pixels.indices where bitmap.pixels[index].a > 0 {
                bitmap.pixels[index].a = 255
            }
            if bitmap.pixels.contains(where: \.isOpaque) { return bitmap }
            throw PetImportError.noFrames
        }
        return try lift(fitted)
    }

    private static func lift(_ image: CGImage) throws -> PetBitmap {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first as? VNInstanceMaskObservation, !result.allInstances.isEmpty else {
            throw PetImportError.noSubject
        }
        let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        return apply(mask: mask, to: image)
    }

    private static func videoBitmaps(url: URL, cutout: Bool) async throws -> [PetBitmap] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw PetImportError.unreadable }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        var images: [CGImage] = []
        for time in PetFramePicker.timestamps(duration: duration) {
            let sample = CMTime(seconds: time, preferredTimescale: 600)
            if let (image, _) = try? await generator.image(at: sample) {
                images.append(image)
            }
        }
        if images.isEmpty { throw PetImportError.noFrames }
        return try collect(images, cutout: cutout)
    }

    private static func downscaled(_ image: CGImage, maxSide: Int) -> CGImage {
        let width = image.width
        let height = image.height
        let longest = max(width, height)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = Double(maxSide) / Double(longest)
        let targetWidth = max(1, Int((Double(width) * scale).rounded()))
        let targetHeight = max(1, Int((Double(height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage() ?? image
    }

    private static func apply(mask: CVPixelBuffer, to image: CGImage) -> PetBitmap {
        var picture = bitmap(from: image)
        let maskImage = cgImage(from: mask) ?? image
        let maskBitmap = bitmap(from: maskImage)
        let width = min(picture.width, maskBitmap.width)
        let height = min(picture.height, maskBitmap.height)
        guard width > 0, height > 0 else { return picture }
        var pixels = picture.pixels
        for y in 0..<height {
            for x in 0..<width {
                let alpha = maskBitmap.pixel(x: x, y: y).luminance
                let index = y * picture.width + x
                if alpha < 16 {
                    pixels[index] = .clear
                } else if index < pixels.count {
                    pixels[index].a = UInt8(min(255, alpha))
                }
            }
        }
        picture.pixels = pixels
        return picture
    }

    private static func cgImage(from buffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: buffer)
        let context = CIContext(options: nil)
        return context.createCGImage(image, from: image.extent)
    }
}
