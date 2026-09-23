@preconcurrency import ApplicationServices
import AppKit

/// 操作対象のウィンドウ。他アプリは AX で、自アプリは NSWindow を直接操作する。
/// （自アプリへの AX 問い合わせは呼び出し元スレッドで処理され、SwiftUI がメインスレッド外で動いてしまうため）
/// 座標はすべてグローバル座標（左上原点）。
enum WindowHandle {
    case accessibility(AXUIElement)
    case own(windowNumber: Int)

    var frame: CGRect? {
        switch self {
        case .accessibility(let window):
            guard let position = WindowLocator.position(of: window),
                  let size = WindowLocator.size(of: window) else { return nil }
            return CGRect(origin: position, size: size)
        case .own(let number):
            return OwnWindow.frame(number)
        }
    }

    @discardableResult
    func setPosition(_ point: CGPoint) -> Bool {
        switch self {
        case .accessibility(let window):
            let result = WindowLocator.setPosition(point, of: window)
            if result != .success { Log.window.error("setPosition failed: \(result.rawValue, privacy: .public)") }
            return result == .success
        case .own(let number):
            return OwnWindow.setPosition(point, of: number)
        }
    }

    /// 左上を固定してサイズを変える
    @discardableResult
    func setSize(_ size: CGSize) -> Bool {
        switch self {
        case .accessibility(let window):
            let result = WindowLocator.setSize(size, of: window)
            if result != .success { Log.window.error("setSize failed: \(result.rawValue, privacy: .public)") }
            return result == .success
        case .own(let number):
            return OwnWindow.setSize(size, of: number)
        }
    }

    func isSame(as other: WindowHandle) -> Bool {
        switch (self, other) {
        case let (.accessibility(a), .accessibility(b)): CFEqual(a, b)
        case let (.own(a), .own(b)): a == b
        default: false
        }
    }

    var appName: String {
        switch self {
        case .accessibility(let window): WindowLocator.appName(of: window)
        case .own: "Btry"
        }
    }
}

/// 自アプリのウィンドウをメインスレッドで操作する。ウィンドウ操作キューから同期的に呼ぶ
enum OwnWindow {
    /// 移動・リサイズの対象にしてよい自アプリのウィンドウか（設定ウィンドウなど。メニューやプレビューは除く）
    static func isMovable(_ number: Int) -> Bool {
        perform(number) { window in
            window.isVisible && window.styleMask.contains(.titled) && !(window is NSPanel)
        } ?? false
    }

    static func frame(_ number: Int) -> CGRect? {
        perform(number) { CoordinateConverter.toGlobal($0.frame) }
    }

    static func setPosition(_ point: CGPoint, of number: Int) -> Bool {
        perform(number) { window in
            let target = CGRect(origin: point, size: window.frame.size)
            window.setFrameOrigin(CoordinateConverter.toAppKit(target).origin)
        } != nil
    }

    static func setSize(_ size: CGSize, of number: Int) -> Bool {
        perform(number) { window in
            // 設定ウィンドウのように中身に合わせてサイズが決まるものは変えない
            guard window.styleMask.contains(.resizable) else { return false }
            let current = CoordinateConverter.toGlobal(window.frame)
            window.setFrame(CoordinateConverter.toAppKit(CGRect(origin: current.origin, size: size)), display: true)
            return true
        } ?? false
    }

    private static func perform<T: Sendable>(_ number: Int, _ body: @MainActor (NSWindow) -> T) -> T? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { NSApp.window(withWindowNumber: number).map(body) }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { NSApp.window(withWindowNumber: number).map(body) }
        }
    }
}
