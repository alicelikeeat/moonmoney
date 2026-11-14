import SwiftData
import SwiftUI
import UIKit

struct RecordDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @Bindable var record: Record
    @State private var confirmDelete = false
    @State private var showPhoto = false

    var body: some View {
        List {
            Group {
                VStack(spacing: 12) {
                    CategoryIcon(symbol: record.displaySymbol, color: record.displayColor, size: 64, filled: true, image: record.displayImage)
                    Text(record.displayTitle)
                        .font(Font.skin(.headline))
                    AmountText(cents: record.amountCents, kind: record.kind, code: record.currencyCode,
                               font: .money(36))
                    if record.currencyCode != AppSettings.shared.baseCurrency {
                        Text("约 \(Money.format(record.baseAmountCents))")
                            .font(Font.skin(.footnote))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 32, tint: record.displayColor.opacity(0.12))
                .plainListRow(top: 12, bottom: 12)

                Section {
                    LabeledContent("类型", value: record.kind.title)
                    LabeledContent("时间", value: record.date.zh("yMMMdEEEE HH:mm"))
                    if record.kind == .transfer {
                        LabeledContent("转出账户", value: record.account?.name ?? "—")
                        LabeledContent("转入账户", value: record.toAccount?.name ?? "—")
                        if record.toAmountCents > 0 {
                            LabeledContent("到账金额", value: Money.format(record.toAmountCents, code: record.toAccount?.currencyCode ?? record.currencyCode))
                        }
                        if record.feeCents > 0 {
                            LabeledContent("手续费", value: Money.format(record.feeCents, code: record.currencyCode))
                        }
                    } else {
                        LabeledContent("分类", value: record.category?.name ?? "未分类")
                        LabeledContent("账户", value: record.account?.name ?? "—")
                    }
                    if !record.note.isEmpty {
                        LabeledContent("备注", value: record.note)
                    }
                    if !record.sortedTags.isEmpty {
                        LabeledContent("标签", value: record.sortedTags.map { "#\($0.name)" }.joined(separator: " "))
                    }
                    if !record.member.isEmpty {
                        LabeledContent("成员", value: record.member)
                    }
                    if record.installmentCount > 1 {
                        LabeledContent("分期", value: "第 \(record.installmentIndex) / \(record.installmentCount) 期")
                    }
                    if record.kind == .expense {
                        Picker("报销", selection: Binding(
                            get: { record.reimbursement },
                            set: { record.reimbursement = $0; try? context.save() }
                        )) {
                            ForEach(ReimbursementState.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    Toggle("计入统计与预算", isOn: Binding(
                        get: { !record.excludedFromStats },
                        set: { record.excludedFromStats = !$0; try? context.save() }
                    ))
                }

                if let data = record.photo, let image = UIImage(data: data) {
                    Section {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(.rect(cornerRadius: 16))
                            .onTapGesture { showPhoto = true }
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    } header: {
 SectionTitle("票据")
 }
                }

                Section {
                    LabeledContent("创建于", value: record.createdAt.zh("yMMMd HH:mm"))
                    if record.isRecurringInstance {
                        Label("由周期记账自动生成", systemImage: "repeat")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(Font.skin(.footnote))
            }
            .listRowBackground(GlassRowBackground())
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackground(tint: record.displayColor) }
        .navigationTitle("账单详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑", systemImage: "pencil") { router.edit(record) }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("删除", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .confirmationDialog("删除这笔账单？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                let target = record
                dismiss()
                // Delete after the pop animation so the view never reads a deleted model.
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    let id = target.uuid
                    context.delete(target)
                    try? context.save()
                    AppServices.recordDeleted(id)
                }
            }
        }
        .fullScreenCover(isPresented: $showPhoto) {
            if let data = record.photo, let image = UIImage(data: data) {
                PhotoViewer(image: image)
            }
        }
    }
}

struct PhotoViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }.onEnded { _ in
                    withAnimation(.smooth) { scale = 1 }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭", systemImage: "xmark", role: .close) { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("票据", image: Image(uiImage: image)))
                    }
                }
        }
    }
}
