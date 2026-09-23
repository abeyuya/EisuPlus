import SwiftUI

struct SettingsView: View {
    @Binding var settings: Settings

    var body: some View {
        Form {
            Section {
                Toggle("一時停止", isOn: $settings.isPaused)
            }

            Section("入力切り替え") {
                Toggle("左⌘の単押しで英数、右⌘の単押しでかな", isOn: $settings.inputSourceSwitchEnabled)
            }

            Section("ウィンドウ移動") {
                Toggle("有効", isOn: $settings.moveEnabled)
                BindingEditor(binding: $settings.moveBinding)
                    .disabled(!settings.moveEnabled)
                Toggle("画面の左端・右端で左半分・右半分にスナップ", isOn: $settings.snapEnabled)
                    .disabled(!settings.moveEnabled)
            }

            Section("ウィンドウリサイズ（右下の角を動かす）") {
                Toggle("有効", isOn: $settings.resizeEnabled)
                BindingEditor(binding: $settings.resizeBinding)
                    .disabled(!settings.resizeEnabled)
            }

            let warnings = settings.bindingWarnings
            if !warnings.isEmpty {
                Section {
                    ForEach(warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct BindingEditor: View {
    @Binding var binding: GestureBinding

    var body: some View {
        LabeledContent("修飾キー") {
            HStack(spacing: 4) {
                ForEach(Modifier.displayOrder, id: \.self) { modifier in
                    Toggle(modifier.symbol, isOn: isOn(modifier))
                        .toggleStyle(.button)
                        .help(modifier.name)
                }
            }
        }
        Picker("操作", selection: $binding.trigger) {
            ForEach(Trigger.allCases, id: \.self) { trigger in
                Text(trigger.label).tag(trigger)
            }
        }
    }

    private func isOn(_ modifier: Modifier) -> Binding<Bool> {
        Binding(
            get: { binding.modifiers.contains(modifier) },
            set: { isOn in
                if isOn { binding.modifiers.insert(modifier) } else { binding.modifiers.remove(modifier) }
            }
        )
    }
}

extension Settings {
    /// 設定画面に表示する、キーバインドの問題点
    var bindingWarnings: [String] {
        var warnings: [String] = []
        let features: [(name: String, enabled: Bool, binding: GestureBinding)] = [
            ("ウィンドウ移動", moveEnabled, moveBinding),
            ("ウィンドウリサイズ", resizeEnabled, resizeBinding),
        ]
        for feature in features where feature.enabled {
            if feature.binding.modifiers.isEmpty {
                warnings.append("\(feature.name): 修飾キーが選ばれていないため無効になっています")
            } else if feature.binding.modifiers == [.command], inputSourceSwitchEnabled {
                warnings.append("\(feature.name): ⌘単独だと、操作後に⌘を離したとき英数/かなが切り替わることがあります")
            }
        }
        if moveEnabled, resizeEnabled, !moveBinding.modifiers.isEmpty, moveBinding == resizeBinding {
            warnings.append("移動とリサイズが同じキーバインドのため、移動が優先されます")
        }
        return warnings
    }
}

extension Modifier {
    static let displayOrder: [Modifier] = [.function, .control, .option, .shift, .command]

    var symbol: String {
        switch self {
        case .function: "fn"
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    var name: String {
        switch self {
        case .function: "fn"
        case .control: "control"
        case .option: "option"
        case .shift: "shift"
        case .command: "command"
        }
    }
}

extension Trigger {
    var label: String {
        switch self {
        case .mouseMove: "マウス移動（クリック不要）"
        case .leftDrag: "左ドラッグ"
        case .rightDrag: "右ドラッグ"
        }
    }
}

extension GestureBinding {
    var label: String {
        let symbols = Modifier.displayOrder.filter(modifiers.contains).map(\.symbol).joined()
        let action = switch trigger {
        case .mouseMove: "マウス移動"
        case .leftDrag: "左ドラッグ"
        case .rightDrag: "右ドラッグ"
        }
        return symbols.isEmpty ? "未設定" : "\(symbols) + \(action)"
    }
}
