@preconcurrency import ApplicationServices
import Foundation
import os

/// ウィンドウの移動・リサイズを専用キューで実行する。
/// AX 呼び出しは重いので、イベントタップのスレッドからは命令を積むだけにし、
/// 位置の更新は最新のものだけを反映する（古いものは捨てる）。
final class WindowOperator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.abeyuya.btry.window-operator", qos: .userInteractive)

    /// タップのスレッドとキューの間で受け渡す、最新のカーソル位置
    private let pending = OSAllocatedUnfairLock<(point: CGPoint?, drainScheduled: Bool)>(initialState: (nil, false))

    // 以下はキュー上でのみ触る
    private var session: Session?

    private struct Session {
        var mode: GestureMode
        var window: AXUIElement?
        var startMouse: CGPoint = .zero
        var startPosition: CGPoint = .zero
    }

    func begin(mode: GestureMode, at point: CGPoint) {
        queue.async { [self] in
            session = Session(mode: mode)
            capture(at: point)
        }
    }

    func update(to point: CGPoint) {
        let shouldSchedule = pending.withLock { state in
            state.point = point
            defer { state.drainScheduled = true }
            return !state.drainScheduled
        }
        guard shouldSchedule else { return }
        queue.async { [self] in drain() }
    }

    func end() {
        queue.async { [self] in
            if let session, let window = session.window {
                Log.window.debug("\(session.mode.rawValue, privacy: .public) end: \(WindowLocator.appName(of: window), privacy: .public)")
            }
            session = nil
        }
    }

    // MARK: - Queue

    private func drain() {
        let point = pending.withLock { state in
            defer { state = (nil, false) }
            return state.point
        }
        guard let point, session != nil else { return }

        // 開始時にウィンドウが無かった場合（デスクトップ上など）は、動かした先で捕まえ直す
        guard let window = session?.window else {
            capture(at: point)
            return
        }

        switch session!.mode {
        case .move:
            let s = session!
            let target = CGPoint(x: s.startPosition.x + (point.x - s.startMouse.x),
                                 y: s.startPosition.y + (point.y - s.startMouse.y))
            let result = WindowLocator.setPosition(target, of: window)
            if result != .success {
                Log.window.error("setPosition failed: \(result.rawValue, privacy: .public)")
            }
        case .resize:
            // フェーズ4で実装
            break
        }
    }

    private func capture(at point: CGPoint) {
        guard let window = WindowLocator.window(at: point),
              let position = WindowLocator.position(of: window) else { return }
        session?.window = window
        session?.startMouse = point
        session?.startPosition = position
        Log.window.debug("\(self.session?.mode.rawValue ?? "?", privacy: .public) begin: \(WindowLocator.appName(of: window), privacy: .public)")
    }
}
