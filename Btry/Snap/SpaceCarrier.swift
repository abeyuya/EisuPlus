import ColorSync
@preconcurrency import CoreGraphics
import Foundation

enum SpaceDirection: Sendable {
    case left, right
}

/// ウィンドウを隣のデスクトップ（操作スペース）へ運ぶ。
/// ウィンドウを別スペースへ移す公開 API は無いため、macOS 標準の挙動
/// 「ウィンドウをつかんだまま操作スペースを切り替えると一緒に移る」を再現する。
/// タイトルバーを合成イベントでつかみ、Mission Control の ⌃← / ⌃→ を送ってから離す。
enum SpaceCarrier {
    /// Btry が合成したイベントの目印（EventTapManager で素通しする）
    static let syntheticEventMarker: Int64 = 0x4254_5259 // "BTRY"

    private static let titleBarOffset: CGFloat = 12
    private static let minimumGrabWidth: CGFloat = 100

    /// 指定位置のディスプレイで、その方向に通常のデスクトップがあるか
    static func hasDesktop(_ direction: SpaceDirection, at point: CGPoint) -> Bool {
        guard let displays = ManagedSpaces.copy() else { return false }
        let entry = displays.first { $0.displayIdentifier == displayUUID(at: point) } ?? (displays.count == 1 ? displays.first : nil)
        guard let entry, let index = entry.spaces.firstIndex(where: { $0.id == entry.currentSpaceID }) else { return false }
        let neighbor = direction == .left ? index - 1 : index + 1
        // フルスクリーンアプリのスペース（type 4 など）には運べないので、通常のデスクトップ（type 0）だけを対象にする
        return entry.spaces.indices.contains(neighbor) && entry.spaces[neighbor].type == 0
    }

    /// ウィンドウを隣のデスクトップへ運ぶ。ウィンドウ操作キューから呼び、完了まで待つ。
    /// 終了後、カーソルを restoreCursor に戻す
    @discardableResult
    static func carry(windowFrame: CGRect, screenFrame: CGRect, direction: SpaceDirection, restoreCursor: CGPoint) -> Bool {
        // タイトルバーのうち画面内に見えている部分の中央をつかむ
        let visibleMinX = max(windowFrame.minX, screenFrame.minX)
        let visibleMaxX = min(windowFrame.maxX, screenFrame.maxX)
        guard visibleMaxX - visibleMinX >= minimumGrabWidth else {
            Log.window.notice("space carry skipped: title bar is not visible enough")
            return false
        }
        let grab = CGPoint(x: (visibleMinX + visibleMaxX) / 2, y: windowFrame.minY + titleBarOffset)

        post(mouse: .mouseMoved, at: grab)
        post(mouse: .leftMouseDown, at: grab)
        usleep(50_000)
        post(mouse: .leftMouseDragged, at: CGPoint(x: grab.x + 1, y: grab.y))
        usleep(50_000)
        postSpaceSwitchShortcut(direction)
        // 操作スペースの切り替えアニメーションが終わるまでつかんだままにする
        usleep(400_000)
        post(mouse: .leftMouseUp, at: CGPoint(x: grab.x + 1, y: grab.y))
        usleep(20_000)
        post(mouse: .mouseMoved, at: restoreCursor)
        Log.window.debug("space carry: \(direction == .left ? "left" : "right", privacy: .public)")
        return true
    }

    // MARK: - Events

    private static func post(mouse type: CGEventType, at point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        // ユーザーが ctrl を押したままなので、明示的に修飾キーを外す（ctrl + クリックが右クリック扱いになるのを防ぐ）
        event.flags = []
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

    private static func displayUUID(at point: CGPoint) -> String? {
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &displayID, &count) == .success, count > 0,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}

/// 非公開 API の CGSCopyManagedDisplaySpaces でディスプレイごとの操作スペース一覧を読む
private enum ManagedSpaces {
    struct Display {
        var displayIdentifier: String
        var currentSpaceID: Int
        var spaces: [(id: Int, type: Int)]
    }

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let functions: (MainConnectionID, CopyManagedDisplaySpaces)? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let connection = dlsym(handle, "CGSMainConnectionID"),
              let copy = dlsym(handle, "CGSCopyManagedDisplaySpaces") else {
            Log.window.error("CGS space functions are unavailable")
            return nil
        }
        return (unsafeBitCast(connection, to: MainConnectionID.self), unsafeBitCast(copy, to: CopyManagedDisplaySpaces.self))
    }()

    static func copy() -> [Display]? {
        guard let (connectionID, copySpaces) = functions,
              let array = copySpaces(connectionID())?.takeRetainedValue() as? [[String: Any]] else { return nil }
        return array.compactMap { dict in
            guard let identifier = dict["Display Identifier"] as? String,
                  let current = (dict["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int,
                  let spaces = dict["Spaces"] as? [[String: Any]] else { return nil }
            return Display(
                displayIdentifier: identifier,
                currentSpaceID: current,
                spaces: spaces.compactMap { space in
                    guard let id = space["ManagedSpaceID"] as? Int else { return nil }
                    return (id, space["type"] as? Int ?? -1)
                }
            )
        }
    }
}
