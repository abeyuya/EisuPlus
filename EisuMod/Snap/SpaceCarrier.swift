// App Store 版では非公開 API（SkyLight）を使えないため、この機能ごと外す
#if !APP_STORE
import ColorSync
@preconcurrency import CoreGraphics
import Foundation

enum SpaceDirection: Sendable {
    case left, right

    var opposite: SpaceDirection { self == .left ? .right : .left }
}

/// ウィンドウを隣のデスクトップ（操作スペース）へ運ぶ。
///
/// 他アプリのウィンドウを別スペースへ移す API は macOS 27 では使えない
/// （SLSMoveWindowsToManagedSpace は無視され、compat ID を使う回避策も拒否される）。
/// そのため Amethyst（Silica の moveToSpace）と同じく、macOS 標準の
/// 「ウィンドウをつかんだまま操作スペースを切り替えると一緒に移る」挙動を再現する。
/// 最小化ボタンの真上（確実にドラッグできるタイトルバー部分）を合成イベントでつかみ、⌃← / ⌃→ を送ってから離す。
enum SpaceCarrier {
    /// EisuMod が合成したイベントの目印（EventTapManager で素通しする）
    static let syntheticEventMarker: Int64 = 0x4549_5355 // "EISU"

    /// 最小化ボタンが取れないウィンドウでつかむ位置（ウィンドウ左上からの距離）
    private static let fallbackGrabOffset = CGPoint(x: 100, y: 5)
    /// つかむ位置を画面端からどれだけ内側に入れるか。
    /// 端の近くでウィンドウをつかむと macOS のタイル配置（左右半分）が待機状態になり、⌃← / ⌃→ が効かなくなる
    private static let screenMargin: CGFloat = 200

    /// 指定位置のディスプレイで、その方向に通常のデスクトップがあるか
    static func hasDesktop(_ direction: SpaceDirection, at point: CGPoint) -> Bool {
        guard let display = ManagedSpaces.display(at: point),
              let index = display.spaces.firstIndex(where: { $0.id == display.currentSpaceID }) else { return false }
        let neighbor = direction == .left ? index - 1 : index + 1
        // フルスクリーンアプリのスペース（type 4 など）には運べないので、通常のデスクトップ（type 0）だけを対象にする
        return display.spaces.indices.contains(neighbor) && display.spaces[neighbor].type == 0
    }

    /// ウィンドウを隣のデスクトップへ運ぶ。ウィンドウ操作キューから呼び、完了まで待つ。
    /// 運べたかどうかにかかわらず、ウィンドウの位置とカーソルは元に戻す
    @discardableResult
    static func carry(_ window: WindowHandle, screen: ScreenInfo, direction: SpaceDirection, restoreCursor: CGPoint) -> Bool {
        guard let originalFrame = window.serverFrame else { return false }

        // ユーザーは端へマウスを押し付け続けているので、そのままだと実際のマウスの動きが合成ドラッグとぶつかる。
        // 運んでいる間だけ、物理的なマウスの動きをカーソルに反映させない
        CGAssociateMouseAndMouseCursorPosition(0)
        defer {
            window.setPosition(originalFrame.origin)
            post(mouse: .mouseMoved, at: restoreCursor)
            CGAssociateMouseAndMouseCursorPosition(1)
        }

        guard let grab = prepareGrabPoint(window, frame: originalFrame, screen: screen) else {
            Log.window.notice("space carry: no grab point for \(window.appName, privacy: .public)")
            return false
        }
        let spaceBefore = ManagedSpaces.display(at: restoreCursor)?.currentSpaceID

        post(mouse: .mouseMoved, at: grab)
        post(mouse: .leftMouseDown, at: grab)
        post(mouse: .leftMouseDragged, at: grab)
        // ウィンドウをつかみきるまで少し待つ
        usleep(80_000)
        postSpaceSwitchShortcut(direction)
        // 操作スペースの切り替えアニメーションが終わるまでつかんだままにする
        usleep(450_000)
        post(mouse: .leftMouseUp, at: grab)
        usleep(50_000)

        // 実際に新しいスペースへ移ったか確かめ、置いていかれたら元のスペースへ戻る
        guard let spaceAfter = ManagedSpaces.display(at: restoreCursor)?.currentSpaceID, spaceAfter != spaceBefore else {
            Log.window.notice("space carry: space did not change")
            return false
        }
        if let number = window.windowNumber, !ManagedSpaces.spaces(ofWindow: number).contains(spaceAfter) {
            Log.window.error("space carry: \(window.appName, privacy: .public) was left behind; switching back")
            postSpaceSwitchShortcut(direction.opposite)
            usleep(450_000)
            return false
        }
        Log.window.debug("space carry: \(window.appName, privacy: .public) → \(direction == .left ? "left" : "right", privacy: .public)")
        return true
    }

    /// つかむ位置を決める。最小化ボタンの真上（Silica と同じ位置）を使い、画面外にあればウィンドウを画面内へずらす
    private static func prepareGrabPoint(_ window: WindowHandle, frame: CGRect, screen: ScreenInfo) -> CGPoint? {
        let offset: CGPoint
        if let button = window.minimizeButtonFrame {
            offset = CGPoint(x: button.midX - frame.minX, y: max(2, (button.minY - frame.minY) / 2))
        } else {
            offset = fallbackGrabOffset
        }

        let bounds = screen.frame.insetBy(dx: screenMargin, dy: 0)
        var origin = frame.origin
        let grabX = origin.x + offset.x
        if grabX < bounds.minX { origin.x += bounds.minX - grabX }
        if grabX > bounds.maxX { origin.x -= grabX - bounds.maxX }
        if origin.y < screen.visibleFrame.minY { origin.y = screen.visibleFrame.minY }

        if origin != frame.origin {
            window.setPosition(origin)
            // 実際に動き終わるまで待つ（動く前につかむと、別の場所をクリックしてしまう）
            var moved = false
            for _ in 0..<15 {
                usleep(20_000)
                if let current = window.serverFrame, abs(current.minX - origin.x) < 2, abs(current.minY - origin.y) < 2 {
                    moved = true
                    break
                }
            }
            guard moved else { return nil }
        }
        return CGPoint(x: origin.x + offset.x, y: origin.y + offset.y)
    }

    // MARK: - Events

    private static func post(mouse type: CGEventType, at point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        // ユーザーが ctrl を押したままなので、明示的に修飾キーを外す（ctrl + クリックが右クリック扱いになるのを防ぐ）
        event.flags = []
        // タイトルバーのダブルクリック（拡大/しまう）と判定されないよう、常にシングルクリックとして送る
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        event.post(tap: .cghidEventTap)
    }

    /// Mission Control の「左/右の操作スペースに移動」（デフォルトの ⌃← / ⌃→）
    private static func postSpaceSwitchShortcut(_ direction: SpaceDirection) {
        let keyCode: CGKeyCode = direction == .left ? 123 : 124
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown) else { continue }
            event.flags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
            event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}

/// 非公開 API（SkyLight）で操作スペースの情報を読む。読み取りは macOS 27 でも動作する
private enum ManagedSpaces {
    struct Display {
        var identifier: String
        var currentSpaceID: Int
        var spaces: [(id: Int, type: Int)]
    }

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private struct Functions: @unchecked Sendable {
        var connectionID: MainConnectionID
        var copyManagedDisplaySpaces: CopyManagedDisplaySpaces
        var copySpacesForWindows: CopySpacesForWindows
    }

    private static let functions: Functions? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let connection = dlsym(handle, "SLSMainConnectionID"),
              let copyDisplays = dlsym(handle, "SLSCopyManagedDisplaySpaces"),
              let copyForWindows = dlsym(handle, "SLSCopySpacesForWindows") else {
            Log.window.error("SkyLight space functions are unavailable")
            return nil
        }
        return Functions(
            connectionID: unsafeBitCast(connection, to: MainConnectionID.self),
            copyManagedDisplaySpaces: unsafeBitCast(copyDisplays, to: CopyManagedDisplaySpaces.self),
            copySpacesForWindows: unsafeBitCast(copyForWindows, to: CopySpacesForWindows.self)
        )
    }()

    /// 指定位置のディスプレイの操作スペース一覧
    static func display(at point: CGPoint) -> Display? {
        let displays = copyDisplays()
        let uuid = displayUUID(at: point)
        // 「ディスプレイごとに個別の操作スペース」がオフの場合は1件（"Main"）だけになる
        return displays.first { $0.identifier == uuid } ?? (displays.count == 1 ? displays.first : nil)
    }

    /// ウィンドウが属している操作スペース
    static func spaces(ofWindow number: Int) -> [Int] {
        guard let functions else { return [] }
        let allSpaces: Int32 = 0x7
        return functions.copySpacesForWindows(functions.connectionID(), allSpaces, [number] as CFArray)?
            .takeRetainedValue() as? [Int] ?? []
    }

    private static func copyDisplays() -> [Display] {
        guard let functions,
              let array = functions.copyManagedDisplaySpaces(functions.connectionID())?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return array.compactMap { dict in
            guard let identifier = dict["Display Identifier"] as? String,
                  let current = (dict["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int,
                  let spaces = dict["Spaces"] as? [[String: Any]] else { return nil }
            return Display(
                identifier: identifier,
                currentSpaceID: current,
                spaces: spaces.compactMap { space in
                    guard let id = space["ManagedSpaceID"] as? Int else { return nil }
                    return (id, space["type"] as? Int ?? -1)
                }
            )
        }
    }

    private static func displayUUID(at point: CGPoint) -> String? {
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &displayID, &count) == .success, count > 0,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
#endif
