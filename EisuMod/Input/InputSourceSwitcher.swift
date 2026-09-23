import Carbon.HIToolbox
@preconcurrency import CoreGraphics
import Foundation

/// 左⌘の単押しで英数、右⌘の単押しでかなに切り替える。
/// 押してから離すまでに他の入力があった場合や、長押しの場合は何もしない。
final class InputSourceSwitcher: EventHandler, @unchecked Sendable {
    private static let longPressThreshold: UInt64 = 500_000_000 // ns

    private let settings: SettingsSnapshot
    /// 単押し候補の ⌘ の keyCode と押下時刻（CGEvent.timestamp）
    private var pending: (keyCode: Int64, timestamp: UInt64)?

    init(settings: SettingsSnapshot) {
        self.settings = settings
    }

    let eventTypes: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .flagsChanged else {
            pending = nil
            return false
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isCommandKey = keyCode == Int64(kVK_Command) || keyCode == Int64(kVK_RightCommand)
        let flags = event.flags.gestureModifiers

        if isCommandKey, flags == .maskCommand {
            pending = (keyCode, event.timestamp)
        } else if isCommandKey, flags.isEmpty, let pending, pending.keyCode == keyCode {
            self.pending = nil
            let elapsed = event.timestamp &- pending.timestamp
            let current = settings.current
            guard elapsed < Self.longPressThreshold, current.inputSourceSwitchEnabled, !current.isPaused else { return false }
            let isLeft = keyCode == Int64(kVK_Command)
            postKey(CGKeyCode(isLeft ? kVK_JIS_Eisu : kVK_JIS_Kana))
            Log.input.debug("command tap: \(isLeft ? "英数" : "かな", privacy: .public)")
        } else {
            pending = nil
        }
        return false
    }

    private func postKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)?.post(tap: .cghidEventTap)
    }
}
