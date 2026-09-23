import AppKit
import os

/// ディスプレイ配置のスナップショット。座標は AX / CGEvent と同じ左上原点のグローバル座標。
struct ScreenInfo: Sendable {
    var frame: CGRect
    var visibleFrame: CGRect
}

/// NSScreen はメインスレッドで読み、ここに保持して任意のスレッドから参照する。
final class ScreenGeometry: Sendable {
    private let lock = OSAllocatedUnfairLock<[ScreenInfo]>(initialState: [])

    @MainActor
    init() {
        reload()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    var screens: [ScreenInfo] { lock.withLock { $0 } }

    @MainActor
    private func reload() {
        let screens = NSScreen.screens.map { screen in
            ScreenInfo(frame: CoordinateConverter.toGlobal(screen.frame),
                       visibleFrame: CoordinateConverter.toGlobal(screen.visibleFrame))
        }
        lock.withLock { $0 = screens }
        Log.window.debug("screens reloaded: \(screens.count, privacy: .public)")
    }
}

/// AppKit（左下原点）とグローバル座標（左上原点）の変換
enum CoordinateConverter {
    /// メインディスプレイの高さ。原点の基準になる
    @MainActor
    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    @MainActor
    static func toGlobal(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    @MainActor
    static func toAppKit(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
