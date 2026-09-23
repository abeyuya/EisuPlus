import SwiftUI

@main
struct EisuModApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("EisuMod", systemImage: model.settingsStore.settings.isPaused ? "keyboard.badge.ellipsis" : "keyboard") {
            MenuContent(model: model, settings: Bindable(model.settingsStore).settings)
        }

        Window("EisuMod 設定", id: SettingsView.windowID) {
            SettingsView(settings: Bindable(model.settingsStore).settings)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

extension SettingsView {
    static let windowID = "settings"
}

private struct MenuContent: View {
    let model: AppModel
    @Binding var settings: Settings
    @Environment(\.openWindow) private var openWindow

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
        Toggle("移動中の画面端スナップ", isOn: $settings.snapEnabled)

        Divider()

        Button("設定…") {
            openWindow(id: SettingsView.windowID)
            NSApplication.shared.activate()
        }
        .keyboardShortcut(",")
        Button("終了") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
