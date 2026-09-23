@preconcurrency import ApplicationServices
import AppKit

/// AX まわりのヘルパー。座標は AX / CGEvent と同じ左上原点のグローバル座標。
enum WindowLocator {
    private static let messagingTimeout: Float = 0.25

    /// 指定位置にある、操作対象にできるウィンドウを返す。excludedBundleIDs のアプリのウィンドウは対象外
    static func window(at point: CGPoint, excludedBundleIDs: Set<String> = []) -> WindowHandle? {
        // 自アプリへの AX 問い合わせは呼び出し元スレッドで処理され、SwiftUI がメインスレッド外で動いてクラッシュする。
        // そのため AX を呼ぶ前に、ウィンドウサーバーの情報で自アプリのウィンドウかどうかを判定し、自アプリなら NSWindow を直接扱う
        let topmost = topmostWindow(at: point)
        let owner = topmost?.pid
        if let topmost, topmost.pid == ProcessInfo.processInfo.processIdentifier {
            return OwnWindow.isMovable(topmost.windowNumber) ? .own(windowNumber: topmost.windowNumber) : nil
        }
        if let owner, !excludedBundleIDs.isEmpty,
           let bundleID = NSRunningApplication(processIdentifier: owner)?.bundleIdentifier,
           excludedBundleIDs.contains(bundleID) {
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)

        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
              let element else { return nil }

        let window: AXUIElement
        if stringValue(element, kAXRoleAttribute) == kAXWindowRole as String {
            window = element
        } else if let found: AXUIElement = elementValue(element, kAXWindowAttribute) {
            window = found
        } else {
            return nil
        }

        if boolValue(window, "AXFullScreen") == true { return nil }

        AXUIElementSetMessagingTimeout(window, messagingTimeout)
        return .accessibility(window)
    }

    static func position(of window: AXUIElement) -> CGPoint? {
        var point = CGPoint.zero
        guard let value: AXValue = axValue(window, kAXPositionAttribute),
              AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(of window: AXUIElement) -> CGSize? {
        var size = CGSize.zero
        guard let value: AXValue = axValue(window, kAXSizeAttribute),
              AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    @discardableResult
    static func setPosition(_ point: CGPoint, of window: AXUIElement) -> AXError {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    @discardableResult
    static func setSize(_ size: CGSize, of window: AXUIElement) -> AXError {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    static func application(of element: AXUIElement) -> AXUIElement {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        return app
    }

    private static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"

    /// AXEnhancedUserInterface を切り替える。無効化時は、もともと有効で実際に無効化できた場合だけ true を返す
    @discardableResult
    static func setEnhancedUserInterface(_ enabled: Bool, of app: AXUIElement) -> Bool {
        if !enabled, boolValue(app, enhancedUserInterfaceAttribute) != true { return false }
        let value = (enabled ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef
        return AXUIElementSetAttributeValue(app, enhancedUserInterfaceAttribute as CFString, value) == .success
    }

    static func appName(of element: AXUIElement) -> String {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
    }

    /// 指定位置で最前面にあるウィンドウの所有プロセスとウィンドウ番号
    private static func topmostWindow(at point: CGPoint) -> (pid: pid_t, windowNumber: Int)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(point),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
            return (pid, number)
        }
        return nil
    }

    // MARK: - Attribute helpers

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func stringValue(_ element: AXUIElement, _ attribute: String) -> String? {
        copyValue(element, attribute) as? String
    }

    private static func boolValue(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (copyValue(element, attribute) as? NSNumber)?.boolValue
    }

    private static func elementValue(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyValue(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = copyValue(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
