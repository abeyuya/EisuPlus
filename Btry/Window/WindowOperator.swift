@preconcurrency import ApplicationServices
import Foundation
import os

/// ウィンドウの移動・リサイズを専用キューで実行する。
/// AX 呼び出しは重いので、イベントタップのスレッドからは命令を積むだけにし、
/// 位置の更新は最新のものだけを反映する（古いものは捨てる）。
final class WindowOperator: @unchecked Sendable {
    private static let minimumSize = CGSize(width: 120, height: 80)

    private let queue = DispatchQueue(label: "com.abeyuya.btry.window-operator", qos: .userInteractive)

    /// タップのスレッドとキューの間で受け渡す、最新のカーソル位置
    private let pending = OSAllocatedUnfairLock<(point: CGPoint?, drainScheduled: Bool)>(initialState: (nil, false))

    // 以下はキュー上でのみ触る
    private var session: Session?

    private struct Session {
        var mode: GestureMode
        var target: Target?
    }

    /// 捕まえたウィンドウと、開始時の状態
    private struct Target {
        var window: AXUIElement
        var app: AXUIElement
        var startMouse: CGPoint
        var startFrame: CGRect
        /// 一時的に無効化した AXEnhancedUserInterface（終了時に戻す）
        var restoresEnhancedUI: Bool
    }

    func begin(mode: GestureMode, at point: CGPoint) {
        queue.async { [self] in
            finishSession()
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
        queue.async { [self] in finishSession() }
    }

    // MARK: - Queue

    private func drain() {
        let point = pending.withLock { state in
            defer { state = (nil, false) }
            return state.point
        }
        guard let point, let session else { return }

        // 開始時にウィンドウが無かった場合（デスクトップ上など）は、動かした先で捕まえ直す
        guard let target = session.target else {
            capture(at: point)
            return
        }

        let dx = point.x - target.startMouse.x
        let dy = point.y - target.startMouse.y
        switch session.mode {
        case .move:
            let result = WindowLocator.setPosition(
                CGPoint(x: target.startFrame.minX + dx, y: target.startFrame.minY + dy), of: target.window)
            if result != .success {
                Log.window.error("setPosition failed: \(result.rawValue, privacy: .public)")
            }
        case .resize:
            resize(target, dx: dx, dy: dy)
        }
    }

    /// 左上を固定し、右下の角を動かす
    private func resize(_ target: Target, dx: CGFloat, dy: CGFloat) {
        let size = CGSize(
            width: max(Self.minimumSize.width, target.startFrame.width + dx),
            height: max(Self.minimumSize.height, target.startFrame.height + dy)
        )
        let result = WindowLocator.setSize(size, of: target.window)
        if result != .success {
            Log.window.error("setSize failed: \(result.rawValue, privacy: .public)")
        }
    }

    private func capture(at point: CGPoint) {
        guard let session,
              let window = WindowLocator.window(at: point),
              let position = WindowLocator.position(of: window),
              let size = WindowLocator.size(of: window) else { return }

        let frame = CGRect(origin: position, size: size)
        let app = WindowLocator.application(of: window)
        // Chrome などは AXEnhancedUserInterface が有効だとサイズ変更にアニメーションが入って重くなる
        let restoresEnhancedUI = session.mode == .resize && WindowLocator.setEnhancedUserInterface(false, of: app)

        self.session?.target = Target(
            window: window,
            app: app,
            startMouse: point,
            startFrame: frame,
            restoresEnhancedUI: restoresEnhancedUI
        )
        Log.window.debug("\(session.mode.rawValue, privacy: .public) begin: \(WindowLocator.appName(of: window), privacy: .public)")
    }

    private func finishSession() {
        if let session, let target = session.target {
            if target.restoresEnhancedUI {
                WindowLocator.setEnhancedUserInterface(true, of: target.app)
            }
            Log.window.debug("\(session.mode.rawValue, privacy: .public) end: \(WindowLocator.appName(of: target.window), privacy: .public)")
        }
        session = nil
    }
}
