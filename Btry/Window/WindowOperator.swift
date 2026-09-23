@preconcurrency import ApplicationServices
import Foundation
import os

/// ウィンドウの移動・リサイズを専用キューで実行する。
/// AX 呼び出しは重いので、イベントタップのスレッドからは命令を積むだけにし、
/// 位置の更新は最新のものだけを反映する（古いものは捨てる）。
final class WindowOperator: @unchecked Sendable {
    private static let minimumSize = CGSize(width: 120, height: 80)
    /// 左右の端に押し付けたまま、隣のデスクトップへ運ぶまで待つ時間
    private static let spaceCarryDelay: TimeInterval = 0.7

    private let queue = DispatchQueue(label: "com.abeyuya.btry.window-operator", qos: .userInteractive)

    /// タップのスレッドとキューの間で受け渡す、最新のカーソル位置
    private let pending = OSAllocatedUnfairLock<(point: CGPoint?, drainScheduled: Bool)>(initialState: (nil, false))

    private let settings: SettingsSnapshot
    private let preview: SnapPreviewWindow

    // 以下はキュー上でのみ触る
    private var session: Session?
    private let snap: SnapController

    private struct Session {
        var mode: GestureMode
        var target: Target?
        /// 移動中にカーソルが入っているスナップ領域
        var snapZone: (zone: SnapZone, frame: CGRect)?
        /// 押し付けている端の方向と、隣のデスクトップへ運ぶ予約
        var carryDirection: SpaceDirection?
        var carryWork: DispatchWorkItem?
    }

    init(settings: SettingsSnapshot, geometry: ScreenGeometry, preview: SnapPreviewWindow) {
        self.settings = settings
        self.preview = preview
        snap = SnapController(geometry: geometry)
    }

    /// 捕まえたウィンドウと、開始時の状態
    private struct Target {
        var window: WindowHandle
        /// AXEnhancedUserInterface を戻す対象のアプリ（他アプリのリサイズ時のみ）
        var app: AXUIElement?
        var startMouse: CGPoint
        var startFrame: CGRect
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
            target.window.setPosition(CGPoint(x: target.startFrame.minX + dx, y: target.startFrame.minY + dy))
            updateSnapZone(at: point)
            updateSpaceCarry(at: point)
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
        target.window.setSize(size)
    }

    private func updateSnapZone(at point: CGPoint) {
        let current = settings.current
        let zone = current.snapEnabled ? snap.zone(at: point, includesMaximize: current.snapTopMaximizeEnabled) : nil
        guard zone?.zone != session?.snapZone?.zone else { return }
        session?.snapZone = zone
        DispatchQueue.main.async { [preview] in
            MainActor.assumeIsolated {
                if let zone { preview.show(zone.frame) } else { preview.hide() }
            }
        }
    }

    /// 左右の端に押し付けたらタイマーを仕掛け、留まり続けたら隣のデスクトップへ運ぶ
    private func updateSpaceCarry(at point: CGPoint) {
        var direction: SpaceDirection?
        if settings.current.spaceCarryEnabled {
            switch snap.zone(at: point, includesMaximize: false)?.zone {
            case .leftHalf: direction = .left
            case .rightHalf: direction = .right
            default: direction = nil
            }
        }
        guard direction != session?.carryDirection else { return }
        session?.carryWork?.cancel()
        session?.carryWork = nil
        session?.carryDirection = direction
        guard let direction else { return }

        let work = DispatchWorkItem { [weak self] in self?.carryToNeighborSpace(direction) }
        session?.carryWork = work
        queue.asyncAfter(deadline: .now() + Self.spaceCarryDelay, execute: work)
    }

    private func carryToNeighborSpace(_ direction: SpaceDirection) {
        guard let session, session.carryDirection == direction, let target = session.target,
              let cursor = CGEvent(source: nil)?.location,
              let screen = snap.screen(at: cursor),
              SpaceCarrier.hasDesktop(direction, at: cursor) else { return }

        // スナップのプレビューは取り消し、運んだ先で改めて判定する
        self.session?.snapZone = nil
        DispatchQueue.main.async { [preview] in
            MainActor.assumeIsolated { preview.hide() }
        }
        let carried = SpaceCarrier.carry(target.window, screen: screen, direction: direction, restoreCursor: cursor)

        // 運べたら、端に押し付けたままなら次の移動でさらに隣へ運ぶ予約が入るようにする。
        // 失敗したら端から離れるまで再試行しない（合成クリックを繰り返さないため）
        if carried { self.session?.carryDirection = nil }
        self.session?.carryWork = nil
        // 運んだ後の位置から追従を続ける
        if let newFrame = target.window.frame {
            self.session?.target?.startFrame = newFrame
            self.session?.target?.startMouse = cursor
        }
    }

    /// スナップしたままのウィンドウを動かし始めたら、スナップ前のサイズに戻す。
    /// カーソルがウィンドウ内の同じ相対位置に来るよう位置も合わせる
    private func unsnapIfNeeded(_ window: WindowHandle, frame: CGRect, mouse: CGPoint) -> CGRect {
        guard let size = snap.unsnapSize(for: window, currentFrame: frame) else { return frame }
        let ratioX = (mouse.x - frame.minX) / frame.width
        let offsetY = mouse.y - frame.minY
        let origin = CGPoint(
            x: mouse.x - ratioX * size.width,
            y: offsetY < size.height ? frame.minY : mouse.y - size.height / 2
        )
        window.setSize(size)
        window.setPosition(origin)
        return window.frame ?? CGRect(origin: origin, size: size)
    }

    private func capture(at point: CGPoint) {
        guard let session,
              let window = WindowLocator.window(at: point, excludedBundleIDs: settings.current.excludedBundleIDs),
              var frame = window.frame else { return }

        if session.mode == .move {
            frame = unsnapIfNeeded(window, frame: frame, mouse: point)
        }
        // Chrome などは AXEnhancedUserInterface が有効だとサイズ変更にアニメーションが入って重くなる
        var app: AXUIElement?
        if session.mode == .resize, case .accessibility(let element) = window {
            let application = WindowLocator.application(of: element)
            if WindowLocator.setEnhancedUserInterface(false, of: application) { app = application }
        }

        self.session?.target = Target(
            window: window,
            app: app,
            startMouse: point,
            startFrame: frame
        )
        Log.window.debug("\(session.mode.rawValue, privacy: .public) begin: \(window.appName, privacy: .public)")
    }

    private func finishSession() {
        session?.carryWork?.cancel()
        if let session, let target = session.target {
            if let zone = session.snapZone {
                snap.apply(zone.frame, to: target.window, originalSize: target.startFrame.size)
                DispatchQueue.main.async { [preview] in
                    MainActor.assumeIsolated { preview.hide() }
                }
            }
            if let app = target.app {
                WindowLocator.setEnhancedUserInterface(true, of: app)
            }
            Log.window.debug("\(session.mode.rawValue, privacy: .public) end: \(target.window.appName, privacy: .public)")
        }
        session = nil
    }
}
