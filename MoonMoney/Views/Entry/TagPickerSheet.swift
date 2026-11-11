import SwiftData
import SwiftUI

struct TagPickerSheet: View {
    @Binding var selection: [RecordTag]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \RecordTag.name) private var tags: [RecordTag]
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("新建标签", text: $newName)
                            .submitLabel(.done)
                            .onSubmit(create)
                        Button("添加", action: create)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    ForEach(tags) { tag in
                        let isOn = selection.contains { $0.uuid == tag.uuid }
                        Button {
                            if isOn {
                                selection.removeAll { $0.uuid == tag.uuid }
                            } else {
                                selection.append(tag)
                            }
                            Haptics.tap()
                        } label: {
                            HStack {
                                Circle().fill(tag.color).frame(width: 10, height: 10)
                                Text(tag.name).foregroundStyle(.primary)
                                Spacer()
                                if isOn {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", systemImage: "checkmark", role: .confirm) { dismiss() }
                }
            }
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let existing = tags.first(where: { $0.name == name }) {
            if !selection.contains(where: { $0.uuid == existing.uuid }) { selection.append(existing) }
        } else {
            let tag = RecordTag(name: name, colorHex: Palette.swatches.randomElement() ?? "#64D2FF")
            context.insert(tag)
            selection.append(tag)
        }
        newName = ""
    }
}
