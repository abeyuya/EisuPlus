@preconcurrency import ApplicationServices
import AppKit
import Observation

/// アプリ全体の状態。権限を監視し、許可されていればイベントタップを動かす。
@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case waitingForPermission
        case running
        case tapFailed
    }

    private(set) var status: Status = .waitingForPermission
    let settingsStore = SettingsStore()

    @ObservationIgnored private let tapManager: EventTapManager
    @ObservationIgnored private var permissionTimer: Timer?

    init() {
        let snapshot = settingsStore.snapshot
        tapManager = EventTapManager(handlers: [
            InputSourceSwitcher(settings: snapshot),
            WindowGestureController(settings: snapshot, windowOperator: WindowOperator()),
        ])

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()

        // 権限の付与・取り消しを追従する。付与直後はタップの作成に失敗することがあるので、その場合も再試行する
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func refresh() {
        let trusted = AXIsProcessTrusted()
        switch (trusted, tapManager.isRunning) {
        case (true, false):
            status = tapManager.start() ? .running : .tapFailed
        case (false, true):
            Log.app.notice("accessibility permission revoked")
            tapManager.stop()
            status = .waitingForPermission
        case (false, false):
            status = .waitingForPermission
        case (true, true):
            status = .running
        }
    }
}
