import PhotosUI
import SwiftUI

/// Create a pet from a photo, GIF, or video, then keep or discard it.
struct PetCustomSection: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var pickerItem: PhotosPickerItem?
    @State private var busy = false
    @State private var draft: PetCustomDraft?
    @State private var failure: PetImportFailure?
    @State private var saved: [PetCustomRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("从照片创造").font(Font.skin(.headline))
            Text("选一张照片、GIF 或短视频。主体会在这台手机上被抠出来，再收成 20×20 的像素宠物，心情和成长跟原来的规则一样。")
                .font(Font.skin(.footnote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos])) {
                Label(busy ? "正在处理…" : "从相册选择", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.inCard(prominent: true))
            .disabled(busy)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await importItem(item, cutout: true) }
            }

            if !saved.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(saved, id: \.id) { record in
                            savedCard(record)
                        }
                    }
                }
            }
        }
        .glassCard(cornerRadius: 24)
        .overlay {
            if busy {
                ProgressView("正在抠图")
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .sheet(item: $draft) { item in
            PetCustomPreview(draft: item) { savedDraft in
                save(savedDraft)
            }
        }
        .alert(item: $failure) { failure in
            Alert(
                title: Text("没法做成宠物"),
                message: Text(failure.message),
                primaryButton: failure.offerWholeImage
                    ? .default(Text("使用整张图片")) { Task { await importItem(failure.item, cutout: false) } }
                    : .default(Text("好")),
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .onAppear { saved = PetCustomLibrary.all() }
    }

    private func savedCard(_ record: PetCustomRecord) -> some View {
        let selected = settings.petCustomID == record.id
        return VStack(spacing: 6) {
            Button {
                settings.petCustomID = record.id
                settings.petName = record.name
                PetCenter.shared.refresh(context: context)
                Haptics.tap()
            } label: {
                VStack(spacing: 6) {
                    rasterThumb(record.frames.first, stage: .adult, mood: .happy)
                        .frame(width: 64, height: 64)
                    Text(record.name).font(Font.skin(.caption)).lineLimit(1)
                }
                .frame(width: 84)
                .padding(.vertical, 8)
                .background {
                    if selected { PixelRect(step: 4).stroke(Color.accentColor, lineWidth: 3) }
                }
            }
            .buttonStyle(.plain)
            Button("删除", role: .destructive) {
                PetCustomLibrary.delete(id: record.id)
                if settings.petCustomID == record.id {
                    settings.petCustomID = ""
                    PetCenter.shared.refresh(context: context)
                }
                saved = PetCustomLibrary.all()
            }
            .font(Font.skin(.caption2))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func rasterThumb(_ raster: PetRaster?, stage: PetStage, mood: PetMood) -> some View {
        if let raster {
            PetRasterView(raster: PetPixelate.styled(raster, mood: mood, stage: stage), scale: stage == .egg ? 1 : stage.scale, centered: true)
        } else {
            Color.clear
        }
    }

    private func importItem(_ item: PhotosPickerItem, cutout: Bool) async {
        busy = true
        defer { busy = false }
        do {
            guard let source = try await item.loadTransferable(type: PickedPetSource.self) else {
                throw PetImportError.unreadable
            }
            let bitmaps = try await PetImporter.bitmaps(from: source, cutout: cutout)
            let rasters = PetPixelate.rasters(from: bitmaps, paletteCount: 8, cropInset: 0)
            guard !rasters.isEmpty else { throw PetImportError.noSubject }
            draft = PetCustomDraft(bitmaps: bitmaps, cutout: cutout, name: settings.petName.isEmpty ? "我的宠物" : settings.petName)
        } catch let error as PetImportError {
            failure = PetImportFailure(item: item, message: error.localizedDescription, offerWholeImage: cutout && error == .noSubject)
        } catch {
            failure = PetImportFailure(item: item, message: PetImportError.unreadable.localizedDescription, offerWholeImage: false)
        }
    }

    private func save(_ draft: PetCustomDraft) {
        let rasters = PetPixelate.rasters(from: draft.bitmaps, paletteCount: draft.paletteCount, cropInset: draft.cropInset)
        guard !rasters.isEmpty else { return }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = PetCustomRecord(
            id: UUID().uuidString,
            name: name.isEmpty ? "我的宠物" : name,
            frames: rasters,
            createdAt: .now
        )
        PetCustomLibrary.save(record)
        settings.petCustomID = record.id
        settings.petName = record.name
        PetCenter.shared.refresh(context: context)
        saved = PetCustomLibrary.all()
        Haptics.success()
    }
}

struct PetCustomDraft: Identifiable {
    let id = UUID()
    var bitmaps: [PetBitmap]
    var paletteCount = 8
    var cropInset = 0.0
    var cutout: Bool
    var name: String
}

struct PetImportFailure: Identifiable {
    let id = UUID()
    var item: PhotosPickerItem
    var message: String
    var offerWholeImage: Bool
}

private struct PetCustomPreview: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: PetCustomDraft
    var onSave: (PetCustomDraft) -> Void

    var body: some View {
        let rasters = PetPixelate.rasters(from: draft.bitmaps, paletteCount: draft.paletteCount, cropInset: draft.cropInset)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    preview(rasters)
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                    if rasters.isEmpty {
                        Text("裁得太紧了，没有剩下像素。把裁切调小一点。")
                            .font(Font.skin(.footnote))
                            .foregroundStyle(.secondary)
                    }
                    TextField("名字", text: $draft.name)
                        .font(Font.skin(.body))
                        .padding(12)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("颜色 \(draft.paletteCount) 种").font(Font.skin(.subheadline))
                        Stepper("颜色", value: $draft.paletteCount, in: 4...12)
                            .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("裁切").font(Font.skin(.subheadline))
                        Slider(value: $draft.cropInset, in: 0...0.35)
                    }
                    if let base = rasters.first {
                        Text("心情和成长").font(Font.skin(.subheadline))
                        HStack {
                            variant(base, mood: .happy, stage: .baby, title: "幼年")
                            variant(base, mood: .happy, stage: .adult, title: "成年")
                            variant(base, mood: .worried, stage: .adult, title: "担心")
                            variant(base, mood: .sleepy, stage: .adult, title: "睡着")
                            variant(base, mood: .normal, stage: .egg, title: "蛋")
                        }
                    }
                    Text(draft.cutout ? "已抠出主体。小组件和灵动岛用第一帧，App 里会播放 GIF 或视频的关键帧。" : "使用的是整张图片。")
                        .font(Font.skin(.caption))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .background { AmbientBackground(tint: .orange) }
            .navigationTitle("预览宠物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", role: .confirm) {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(rasters.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func preview(_ rasters: [PetRaster]) -> some View {
        if rasters.isEmpty {
            ContentUnavailableView("没有像素", systemImage: "photo", description: Text("把裁切调松一点。"))
        } else {
            TimelineView(.animation(minimumInterval: 0.28)) { timeline in
                let index = rasters.count == 1 ? 0 : Int(timeline.date.timeIntervalSinceReferenceDate / 0.28) % rasters.count
                PetRasterView(raster: PetPixelate.styled(rasters[index], mood: .happy, stage: .adult), scale: 1, centered: true)
            }
        }
    }

    private func variant(_ raster: PetRaster, mood: PetMood, stage: PetStage, title: String) -> some View {
        VStack(spacing: 4) {
            PetRasterView(raster: PetPixelate.styled(raster, mood: mood, stage: stage), scale: stage.scale, centered: true)
                .frame(width: 48, height: 48)
            Text(title).font(Font.skin(.caption2)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
