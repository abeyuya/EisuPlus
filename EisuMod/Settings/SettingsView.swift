import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Binding var settings: Settings
    @State private var loginItem = LoginItem()

    var body: some View {
        Form {
            Section {
                Toggle("一時停止", isOn: $settings.isPaused)
                Toggle("ログイン時に起動", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                if let error = loginItem.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
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
                Toggle("画面の上端で最大化", isOn: $settings.snapTopMaximizeEnabled)
                    .disabled(!settings.moveEnabled || !settings.snapEnabled)
                #if !APP_STORE
                Toggle("左端・右端に押し付けたまま待つと隣のデスクトップへ移動", isOn: $settings.spaceCarryEnabled)
                    .disabled(!settings.moveEnabled)
                #endif
            }

            Section("ウィンドウリサイズ（右下の角を動かす）") {
                Toggle("有効", isOn: $settings.resizeEnabled)
                BindingEditor(binding: $settings.resizeBinding)
                    .disabled(!settings.resizeEnabled)
            }

            Section("除外アプリ（移動・リサイズ・スナップをしない）") {
                ExcludedAppsEditor(bundleIDs: $settings.excludedBundleIDs)
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

private struct ExcludedAppsEditor: View {
    @Binding var bundleIDs: Set<String>

    var body: some View {
        ForEach(bundleIDs.sorted(), id: \.self) { bundleID in
            HStack {
                AppLabel(bundleID: bundleID)
                Spacer()
                Button {
                    bundleIDs.remove(bundleID)
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("除外を解除")
            }
        }
        HStack {
            Menu("起動中のアプリから追加") {
                ForEach(runningApps, id: \.bundleID) { app in
                    Button(app.name) { bundleIDs.insert(app.bundleID) }
                }
            }
            .fixedSize()
            Button("アプリを選んで追加…", action: chooseApp)
        }
    }

    private var runningApps: [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { (app.localizedName ?? $0, $0) } }
            .filter { !bundleIDs.contains($0.1) }
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier { bundleIDs.insert(bundleID) }
        }
    }
}

private struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 6) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
        }
        .help(bundleID)
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
