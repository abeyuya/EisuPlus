import SwiftUI

@main
struct BtryApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Btry", systemImage: model.settingsStore.settings.isPaused ? "keyboard.badge.ellipsis" : "keyboard") {
            MenuContent(model: model, settings: Bindable(model.settingsStore).settings)
        }
    }
}

private struct MenuContent: View {
    let model: AppModel
    @Binding var settings: Settings

    var body: some View {
        switch model.status {
        case .running:
            Text(settings.isPaused ? "一時停止中" : "稼働中")
        case .waitingForPermission:
            Text("アクセシビリティ権限が必要です")
            Button("アクセシビリティ設定を開く…") { model.openAccessibilitySettings() }
        case .tapFailed:
            Text("イベントタップの起動に失敗しました（再試行中）")
        }

        Divider()

        Toggle("一時停止", isOn: $settings.isPaused)
        Toggle("⌘単押しで英数/かな", isOn: $settings.inputSourceSwitchEnabled)
        Toggle("ウィンドウ移動（\(settings.moveBinding.label)）", isOn: $settings.moveEnabled)
        Toggle("ウィンドウリサイズ（\(settings.resizeBinding.label)）", isOn: $settings.resizeEnabled)

        Divider()

        Button("終了") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private extension GestureBinding {
    var label: String {
        let order: [Modifier] = [.function, .control, .option, .shift, .command]
        let symbols = order.filter(modifiers.contains).map { modifier in
            switch modifier {
            case .function: "fn"
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            }
        }.joined()
        let action = switch trigger {
        case .mouseMove: "マウス移動"
        case .leftDrag: "左ドラッグ"
        case .rightDrag: "右ドラッグ"
        }
        return "\(symbols) + \(action)"
    }
}
