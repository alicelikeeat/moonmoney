import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Export, import, restore and erase.
struct DataManagementView: View {
    @Environment(\.modelContext) private var context
    @Query private var allRecords: [Record]
    @Query(sort: \Ledger.order) private var ledgers: [Ledger]

    private enum ImportKind { case csv, backup }
    private struct ExportItem: Identifiable {
        let url: URL
        var continueToErase = false
        var id: String { url.absoluteString }
    }

    @State private var exportItem: ExportItem?
    @State private var importKind: ImportKind?
    @State private var pendingRestore: URL?
    @State private var includePhotos = true
    @State private var resetAppearance = false
    @State private var askErase = false
    @State private var typedConfirm = false
    @State private var confirmText = ""
    @State private var confirmSample = false
    @State private var working = false
    @State private var message: String?

    var body: some View {
        List {
            Group {
                Section {
                    Button { exportBackup(thenErase: false) } label: {
                        SettingsLabel("导出完整备份", symbol: "externaldrive.fill.badge.icloud", color: .blue)
                    }
                    Toggle(isOn: $includePhotos) {
                        SettingsLabel("备份包含票据照片", symbol: "photo.stack.fill", color: .purple)
                    }
                    Button { exportCSV() } label: {
                        SettingsLabel("导出表格（CSV）", symbol: "tablecells.fill", color: .green)
                    }
                } header: {
                    Text("导出")
                } footer: {
                    Text("完整备份包含所有账本、账单、账户、分类、预算、周期记账、存钱目标、借贷、自定义图标和主要设置，可用于换机或恢复。CSV 适合用 Excel / Numbers 查看。")
                }

                Section {
                    Button { importKind = .backup } label: {
                        SettingsLabel("从完整备份恢复", symbol: "arrow.counterclockwise.circle.fill", color: .orange)
                    }
                    Button { importKind = .csv } label: {
                        SettingsLabel("从 CSV 导入", symbol: "square.and.arrow.down.fill", color: .gray)
                    }
                    Button { confirmSample = true } label: {
                        SettingsLabel("生成示例数据", symbol: "wand.and.stars", color: .pink)
                    }
                } header: {
                    Text("导入")
                } footer: {
                    Text("从备份恢复会替换当前全部数据；CSV 导入会追加到当前账本。")
                }

                Section {
                    Toggle("同时重置自定义背景", isOn: $resetAppearance)
                    Button(role: .destructive) {
                        askErase = true
                    } label: {
                        Label("清空所有数据", systemImage: "trash.fill")
                            .foregroundStyle(Color.expense)
                    }
                } header: {
                    Text("危险操作")
                } footer: {
                    Text("会删除所有账本、账单、账户、分类、预算、周期记账、存钱目标和借贷，并恢复为初始的默认分类与账户。此操作无法撤销，建议先导出备份。")
                }
            }
            .listRowBackground(GlassRowBackground())
        }
        .pageBackground(tint: .red)
        .navigationTitle("数据管理")
        .overlay {
            if working {
                ProgressView()
                    .controlSize(.large)
                    .padding(24)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
        }
        .sheet(item: $exportItem) { item in
            let proceed: (() -> Void)? = item.continueToErase ? {
                exportItem = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    confirmText = ""
                    typedConfirm = true
                }
            } : nil
            ExportSheet(url: item.url, onContinue: proceed)
                .presentationDetents([.medium, .large])
        }
        .fileImporter(
            isPresented: Binding(get: { importKind != nil }, set: { if !$0 { importKind = nil } }),
            allowedContentTypes: importKind == .backup ? [.json] : [.commaSeparatedText, .plainText]
        ) { result in
            let kind = importKind
            importKind = nil
            guard case .success(let url) = result else { return }
            if kind == .backup {
                pendingRestore = url
            } else {
                importCSV(url)
            }
        }
        .confirmationDialog("清空所有数据？", isPresented: $askErase, titleVisibility: .visible) {
            Button("先导出备份，再清空") { exportBackup(thenErase: true) }
            Button("不备份，直接清空", role: .destructive) {
                confirmText = ""
                typedConfirm = true
            }
        } message: {
            Text("共 \(allRecords.count) 笔账单将被删除。")
        }
        .alert("最后确认", isPresented: $typedConfirm) {
            TextField("输入「清空」", text: $confirmText)
            Button("取消", role: .cancel) {}
            Button("清空所有数据", role: .destructive) { erase() }
                .disabled(confirmText.trimmingCharacters(in: .whitespaces) != "清空")
        } message: {
            Text("请输入「清空」两个字以确认。数据删除后无法恢复。")
        }
        .alert("用备份替换当前数据？", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })) {
            Button("取消", role: .cancel) { pendingRestore = nil }
            Button("恢复", role: .destructive) {
                if let url = pendingRestore { restore(url) }
                pendingRestore = nil
            }
        } message: {
            Text("当前的 \(allRecords.count) 笔账单等全部数据会被备份中的内容替换。")
        }
        .confirmationDialog("在当前账本生成约 3 个月的示例账单？", isPresented: $confirmSample, titleVisibility: .visible) {
            Button("生成") {
                Seed.insertSampleRecords(into: context)
                WidgetSync.reload()
                Haptics.success()
            }
        }
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: Actions

    private func exportBackup(thenErase: Bool) {
        working = true
        defer { working = false }
        do {
            let url = try BackupService.export(context: context, includePhotos: includePhotos)
            exportItem = ExportItem(url: url, continueToErase: thenErase)
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    private func exportCSV() {
        do {
            exportItem = ExportItem(url: try CSVService.export(records: allRecords, ledgers: ledgers))
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importCSV(_ url: URL) {
        do {
            let outcome = try CSVService.importCSV(from: url, into: context)
            Spotlight.reindexAll(context: context)
            WidgetSync.reload()
            message = "已导入 \(outcome.imported) 笔" + (outcome.skipped > 0 ? "，跳过 \(outcome.skipped) 行" : "")
        } catch {
            message = "导入失败：请确认文件包含「日期」和「金额」列。"
        }
    }

    private func restore(_ url: URL) {
        working = true
        defer { working = false }
        do {
            let summary = try BackupService.restore(from: url, context: context)
            Haptics.success()
            message = "恢复完成：\(summary.records) 笔账单、\(summary.accounts) 个账户、\(summary.categories) 个分类。"
        } catch {
            message = "恢复失败：这不是有效的 MoonMoney 备份文件。"
        }
    }

    private func erase() {
        working = true
        defer { working = false }
        do {
            try BackupService.eraseAll(context: context, resetAppearance: resetAppearance)
            Haptics.success()
            message = "已清空所有数据，并恢复了默认分类和账户。"
        } catch {
            message = "清空失败：\(error.localizedDescription)"
        }
    }
}

/// Shows an exported file with Share and Save-to-Files actions.
struct ExportSheet: View {
    let url: URL
    var onContinue: (() -> Void)? = nil
    @State private var savingToFiles = false
    @State private var saved = false
    @State private var moveURL: URL?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: url.pathExtension == "json" ? "externaldrive.fill.badge.checkmark" : "doc.text.fill")
                .font(.system(size: 46))
                .foregroundStyle(.tint)
            Text(url.lastPathComponent)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(url.pathExtension == "json" ? "可在任意设备的 MoonMoney 中「从完整备份恢复」。" : "可用 Numbers、Excel 打开，也可以再次导入。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                moveURL = copyForMove()
                savingToFiles = moveURL != nil
            } label: {
                Label(saved ? "已存储到「文件」" : "存储到「文件」", systemImage: saved ? "checkmark.circle.fill" : "folder.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            ShareLink(item: url) {
                Label("分享（AirDrop / 微信 / 邮件）", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            if let onContinue {
                Button("已保存，继续清空数据", role: .destructive, action: onContinue)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .fileMover(isPresented: $savingToFiles, file: moveURL) { result in
            if case .success = result {
                saved = true
                Haptics.success()
            }
        }
    }

    /// fileMover moves the file, so hand it a copy and keep the original for sharing.
    private func copyForMove() -> URL? {
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try? FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
        let target = copy.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.copyItem(at: url, to: target)
        return target
    }
}
