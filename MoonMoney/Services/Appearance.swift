import AVFoundation
import ImageIO
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Custom background

enum BackgroundKind: String, Codable {
    case none, image, gif, video
}

/// User-chosen wallpaper behind every screen: a photo, an animated GIF or a looping video.
@MainActor
@Observable
final class BackgroundStore {
    static let shared = BackgroundStore()

    private(set) var kind: BackgroundKind
    /// Bumped whenever the media changes so views reload it.
    private(set) var version = 0

    var blur: Double { didSet { defaults.set(blur, forKey: "bg.blur") } }
    var dim: Double { didSet { defaults.set(dim, forKey: "bg.dim") } }
    /// Keep the colorful mesh tint on top of the media.
    var tintOverlay: Bool { didSet { defaults.set(tintOverlay, forKey: "bg.tint") } }
    var playVideo: Bool { didSet { defaults.set(playVideo, forKey: "bg.play") } }
    /// Use the more transparent "clear" Liquid Glass for list sections.
    var clearGlass: Bool { didSet { defaults.set(clearGlass, forKey: "bg.clearGlass") } }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private(set) var cachedImage: UIImage?
    @ObservationIgnored private(set) var cachedGIF: UIImage?

    private init() {
        kind = BackgroundKind(rawValue: defaults.string(forKey: "bg.kind") ?? "") ?? .none
        blur = defaults.object(forKey: "bg.blur") as? Double ?? 0
        dim = defaults.object(forKey: "bg.dim") as? Double ?? 0.15
        tintOverlay = defaults.object(forKey: "bg.tint") as? Bool ?? false
        playVideo = defaults.object(forKey: "bg.play") as? Bool ?? true
        clearGlass = defaults.bool(forKey: "bg.clearGlass")
        loadCaches()
    }

    var isActive: Bool { kind != .none }

    var mediaURL: URL {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("Background", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext: String = switch kind {
        case .video: "mov"
        case .gif: "gif"
        default: "jpg"
        }
        return dir.appendingPathComponent("background.\(ext)")
    }

    // MARK: Updating

    /// Stores image data; GIFs with more than one frame stay animated.
    func setImage(data: Data) throws {
        clearFiles()
        if Self.isAnimatedGIF(data) {
            kind = .gif
            try data.write(to: mediaURL, options: .atomic)
        } else {
            guard let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
            kind = .image
            let resized = image.preparingThumbnail(of: Self.fitSize(image.size, max: 2400)) ?? image
            try resized.jpegData(compressionQuality: 0.88)?.write(to: mediaURL, options: .atomic)
        }
        commit()
    }

    func setVideo(from source: URL) throws {
        clearFiles()
        kind = .video
        let target = mediaURL
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)
        commit()
    }

    func reset() {
        clearFiles()
        kind = .none
        commit()
    }

    private func commit() {
        defaults.set(kind.rawValue, forKey: "bg.kind")
        loadCaches()
        version += 1
        BackgroundVideoPlayer.shared.reload()
    }

    private func clearFiles() {
        let dir = mediaURL.deletingLastPathComponent()
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
        cachedImage = nil
        cachedGIF = nil
    }

    private func loadCaches() {
        switch kind {
        case .image: cachedImage = UIImage(contentsOfFile: mediaURL.path)
        case .gif: cachedGIF = Self.animatedImage(at: mediaURL)
        default: break
        }
    }

    // MARK: GIF decoding

    nonisolated static func isAnimatedGIF(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String? else { return false }
        return type == UTType.gif.identifier && CGImageSourceGetCount(source) > 1
    }

    nonisolated static func animatedImage(at url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        let step = max(1, count / 150) // cap memory for very long GIFs
        var frames: [UIImage] = []
        var duration: Double = 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1200,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        for index in stride(from: 0, to: count, by: step) {
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            duration += frameDuration(source, index: index) * Double(step)
        }
        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: max(duration, 0.1))
    }

    nonisolated private static func frameDuration(_ source: CGImageSource, index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return 0.1 }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0
        let delay = unclamped > 0 ? unclamped : (gif[kCGImagePropertyGIFDelayTime] as? Double ?? 0.1)
        return delay < 0.02 ? 0.1 : delay
    }

    nonisolated private static func fitSize(_ size: CGSize, max side: CGFloat) -> CGSize {
        let scale = min(1, side / Swift.max(size.width, size.height))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

// MARK: - Shared looping video player

/// One muted looping player shared by every screen's background layer.
@MainActor
final class BackgroundVideoPlayer {
    static let shared = BackgroundVideoPlayer()

    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    private init() {
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        reload()
    }

    func reload() {
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        let store = BackgroundStore.shared
        guard store.kind == .video else { return }
        let item = AVPlayerItem(url: store.mediaURL)
        looper = AVPlayerLooper(player: player, templateItem: item)
        if store.playVideo { player.play() }
    }

    func setActive(_ active: Bool) {
        guard BackgroundStore.shared.kind == .video else { return }
        if active && BackgroundStore.shared.playVideo { player.play() } else { player.pause() }
    }
}

/// Picks videos from the photo library as a file.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let target = FileManager.default.temporaryDirectory.appendingPathComponent("picked-\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: target)
            return PickedMovie(url: target)
        }
    }
}

// MARK: - Views

struct CustomBackgroundView: View {
    @Environment(\.colorScheme) private var scheme
    private var store: BackgroundStore { BackgroundStore.shared }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                media
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .blur(radius: store.blur)
                Color.black.opacity(store.dim)
                if store.tintOverlay {
                    LinearGradient(colors: [.purple.opacity(0.25), .clear, .orange.opacity(0.2)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        }
        .id(store.version)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var media: some View {
        switch store.kind {
        case .image:
            if let image = store.cachedImage {
                Image(uiImage: image).resizable().scaledToFill()
            }
        case .gif:
            if let gif = store.cachedGIF {
                AnimatedImageView(image: gif)
            }
        case .video:
            LoopingVideoView()
        case .none:
            EmptyView()
        }
    }
}

private struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.startAnimating()
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if view.image !== image {
            view.image = image
            view.startAnimating()
        }
    }
}

private struct LoopingVideoView: UIViewRepresentable {
    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = BackgroundVideoPlayer.shared.player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {}
}

// MARK: - Alternate app icons

struct AppIconOption: Identifiable, Hashable {
    /// nil = primary icon.
    let iconName: String?
    let title: String
    let preview: String

    var id: String { iconName ?? "default" }

    static let all: [AppIconOption] = [
        AppIconOption(iconName: nil, title: "月光", preview: "IconPreview-Default"),
        AppIconOption(iconName: "AppIcon-Midnight", title: "深夜", preview: "IconPreview-Midnight"),
        AppIconOption(iconName: "AppIcon-Sunset", title: "日落", preview: "IconPreview-Sunset"),
        AppIconOption(iconName: "AppIcon-Mint", title: "薄荷", preview: "IconPreview-Mint"),
        AppIconOption(iconName: "AppIcon-Sakura", title: "樱花", preview: "IconPreview-Sakura"),
        AppIconOption(iconName: "AppIcon-Mono", title: "极简", preview: "IconPreview-Mono"),
        AppIconOption(iconName: "AppIcon-Gold", title: "鎏金", preview: "IconPreview-Gold"),
    ]
}
