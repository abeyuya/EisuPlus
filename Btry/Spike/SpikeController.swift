import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics
import Carbon.HIToolbox
import Observation

/// フェーズ0 スパイク: macOS 27 で以下が動くかを検証する。
/// - アクティブな CGEventTap（イベントの握りつぶし）
/// - AX によるカーソル下ウィンドウの取得と移動（ctrl + 左ドラッグ）
/// - 左右⌘単押しでの英数/かな切り替え（JIS キーイベントの送出）
///
/// 簡単のためタップはメインスレッドの RunLoop で動かす。本実装では専用スレッドに移す。
@MainActor
@Observable
final class SpikeController {
    private(set) var status = "起動中…"

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var permissionTimer: Timer?

    // ウィンドウ移動の状態
    @ObservationIgnored private var dragWindow: AXUIElement?
    @ObservationIgnored private var dragStartMouse: CGPoint = .zero
    @ObservationIgnored private var dragStartWindow: CGPoint = .zero

    // ⌘単押しの状態
    @ObservationIgnored private var pendingCommandKey: Int64?

    private static let relevantFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    init() {
        SpikeLog.write("=== spike launched (macOS \(ProcessInfo.processInfo.operatingSystemVersionString)) ===")
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            startTap()
        } else {
            status = "アクセシビリティ権限を待機中…"
            SpikeLog.write("not trusted yet; polling")
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated { [weak self] in
                    guard let self, AXIsProcessTrusted() else { return }
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                    SpikeLog.write("trusted")
                    self.startTap()
                }
            }
        }
    }

    // MARK: - Event tap

    private func startTap() {
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<SpikeController>.fromOpaque(refcon).takeUnretainedValue()
            return MainActor.assumeIsolated {
                controller.handle(type: type, event: event)
            }
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            status = "❌ CGEventTap の作成に失敗"
            SpikeLog.write("tapCreate FAILED")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        status = "✅ タップ稼働中"
        SpikeLog.write("tapCreate OK")
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            SpikeLog.write("tap disabled (\(type.rawValue)); re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)

        case .flagsChanged:
            handleCommandTap(event)
            return Unmanaged.passUnretained(event)

        case .keyDown:
            pendingCommandKey = nil
            return Unmanaged.passUnretained(event)

        case .rightMouseDown:
            pendingCommandKey = nil
            return Unmanaged.passUnretained(event)

        case .leftMouseDown:
            pendingCommandKey = nil
            let flags = event.flags.intersection(Self.relevantFlags)
            guard flags == .maskControl else { return Unmanaged.passUnretained(event) }
            beginDrag(at: event.location)
            // ウィンドウが取れなかったときもクリックは握りつぶす（コンテキストメニュー抑止の検証）
            return nil

        case .leftMouseDragged:
            guard dragWindow != nil else { return Unmanaged.passUnretained(event) }
            moveDrag(to: event.location)
            return nil

        case .leftMouseUp:
            guard dragWindow != nil else { return Unmanaged.passUnretained(event) }
            SpikeLog.write("drag end")
            dragWindow = nil
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - ⌘単押し → 英数/かな

    private func handleCommandTap(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isCommandKey = keyCode == Int64(kVK_Command) || keyCode == Int64(kVK_RightCommand)
        let flags = event.flags.intersection(Self.relevantFlags)

        if isCommandKey, flags == .maskCommand {
            // ⌘だけが押された
            pendingCommandKey = keyCode
        } else if isCommandKey, flags.isEmpty, let pending = pendingCommandKey, pending == keyCode {
            // 他の入力を挟まずに離された
            pendingCommandKey = nil
            let target = keyCode == Int64(kVK_Command) ? kVK_JIS_Eisu : kVK_JIS_Kana
            postKey(CGKeyCode(target))
            SpikeLog.write("command tap: \(keyCode == Int64(kVK_Command) ? "left → 英数" : "right → かな")")
        } else {
            pendingCommandKey = nil
        }
    }

    private func postKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)?.post(tap: .cghidEventTap)
    }

    // MARK: - ウィンドウ移動

    private func beginDrag(at point: CGPoint) {
        guard let window = Self.window(at: point) else {
            SpikeLog.write("drag begin: no window at \(point)")
            return
        }
        guard let position = Self.position(of: window) else {
            SpikeLog.write("drag begin: failed to read position")
            return
        }
        dragWindow = window
        dragStartMouse = point
        dragStartWindow = position
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"
        SpikeLog.write("drag begin: \(appName) window at \(position)")
    }

    private func moveDrag(to point: CGPoint) {
        guard let dragWindow else { return }
        var newPosition = CGPoint(
            x: dragStartWindow.x + (point.x - dragStartMouse.x),
            y: dragStartWindow.y + (point.y - dragStartMouse.y)
        )
        guard let value = AXValueCreate(.cgPoint, &newPosition) else { return }
        let result = AXUIElementSetAttributeValue(dragWindow, kAXPositionAttribute as CFString, value)
        if result != .success {
            SpikeLog.write("set position failed: \(result.rawValue)")
        }
    }

    // MARK: - AX helpers

    private static func window(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element)
        guard result == .success, let element else {
            SpikeLog.write("elementAtPosition failed: \(result.rawValue)")
            return nil
        }
        if stringAttribute(element, kAXRoleAttribute) == kAXWindowRole as String {
            return element
        }
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else {
            return nil
        }
        return (window as! AXUIElement)
    }

    private static func position(of window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
