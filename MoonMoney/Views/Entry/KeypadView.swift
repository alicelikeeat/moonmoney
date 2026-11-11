import SwiftUI

/// Calculator keypad built from Liquid Glass buttons.
///
///   7  8  9  ⌫
///   4  5  6  +   (hold for ×)
///   1  2  3  −   (hold for ÷)
///   .  0  再记 完成/=
struct KeypadView: View {
    @Binding var input: KeypadInput
    var tint: Color
    var isEditing: Bool
    var onDone: () -> Void
    var onAgain: () -> Void

    @State private var tapCount = 0

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    digit("7"); digit("8"); digit("9")
                    backspaceKey
                }
                GridRow {
                    digit("4"); digit("5"); digit("6")
                    operatorKey(primary: "+", secondary: "×")
                }
                GridRow {
                    digit("1"); digit("2"); digit("3")
                    operatorKey(primary: "−", secondary: "÷")
                }
                GridRow {
                    digit(".")
                    digit("0")
                    if isEditing {
                        key {
                            input.clear()
                        } label: {
                            Text("清空").font(.headline)
                        }
                    } else {
                        key(action: onAgain) {
                            Text("再记").font(.headline)
                        }
                    }
                    doneKey
                }
            }
        }
        .sensoryFeedback(.selection, trigger: tapCount) { _, _ in AppSettings.shared.hapticsEnabled }
    }

    private func digit(_ value: String) -> some View {
        key {
            input.type(value)
        } label: {
            Text(value).font(.title2.weight(.medium))
        }
    }

    private var backspaceKey: some View {
        Menu {
            Button("清空", systemImage: "trash", role: .destructive) { input.clear() }
        } label: {
            keyLabel {
                Image(systemName: "delete.left").font(.title3)
            }
        } primaryAction: {
            tapCount += 1
            input.backspace()
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 16))
    }

    private func operatorKey(primary: String, secondary: String) -> some View {
        Menu {
            Button(secondary) {
                tapCount += 1
                input.type(secondary)
            }
        } label: {
            keyLabel {
                VStack(spacing: 0) {
                    Text(primary).font(.title2.weight(.medium))
                    Text(secondary).font(.caption2).foregroundStyle(.secondary)
                }
            }
        } primaryAction: {
            tapCount += 1
            input.type(primary)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 16))
    }

    private var doneKey: some View {
        Button {
            tapCount += 1
            onDone()
        } label: {
            Text(input.hasOperator ? "=" : (isEditing ? "保存" : "完成"))
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(.rect)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .tint(tint)
    }

    private func key<Label: View>(action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button {
            tapCount += 1
            action()
        } label: {
            keyLabel(label)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 16))
    }

    private func keyLabel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(.primary)
            .contentShape(.rect)
    }
}
