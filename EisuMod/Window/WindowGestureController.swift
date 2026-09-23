@preconcurrency import CoreGraphics
import Foundation

/// 修飾キー + マウス操作を移動・リサイズのジェスチャとして判定する状態機械。
/// イベントタップのスレッドで動き、実際のウィンドウ操作は WindowOperator に任せる。
final class WindowGestureController: EventHandler, @unchecked Sendable {
    private let settings: SettingsSnapshot
    private let windowOperator: WindowOperator

    private var active: (mode: GestureMode, binding: GestureBinding)?

    init(settings: SettingsSnapshot, windowOperator: WindowOperator) {
        self.settings = settings
        self.windowOperator = windowOperator
    }

    let eventTypes: [CGEventType] = [
        .flagsChanged, .mouseMoved,
        .leftMouseDown, .leftMouseDragged, .leftMouseUp,
        .rightMouseDown, .rightMouseDragged, .rightMouseUp,
    ]

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        let flags = event.flags.gestureModifiers

        switch type {
        case .flagsChanged:
            // マウス移動方式は、修飾キーが一致しなくなったら終了する
            if let active, active.binding.trigger == .mouseMove, active.binding.flags != flags {
                end()
            }
            return false

        case .mouseMoved:
            if let active, active.binding.trigger == .mouseMove {
                windowOperator.update(to: event.location)
            } else if active == nil, let match = binding(for: .mouseMove, flags: flags) {
                begin(match, at: event.location)
            }
            return false

        case .leftMouseDown, .rightMouseDown:
            let trigger: Trigger = type == .leftMouseDown ? .leftDrag : .rightDrag
            guard active == nil, let match = binding(for: trigger, flags: flags) else { return false }
            begin(match, at: event.location)
            // ctrl + クリックが右クリック扱いになるのを防ぐため握りつぶす
            return true

        case .leftMouseDragged, .rightMouseDragged:
            guard let active, active.binding.trigger == dragTrigger(for: type) else { return false }
            windowOperator.update(to: event.location)
            return true

        case .leftMouseUp, .rightMouseUp:
            guard let active, active.binding.trigger == dragTrigger(for: type) else { return false }
            windowOperator.update(to: event.location)
            end()
            return true

        default:
            return false
        }
    }

    private func binding(for trigger: Trigger, flags: CGEventFlags) -> (mode: GestureMode, binding: GestureBinding)? {
        settings.current.activeBindings.first { $0.binding.trigger == trigger && $0.binding.flags == flags }
    }

    private func dragTrigger(for type: CGEventType) -> Trigger {
        switch type {
        case .rightMouseDragged, .rightMouseUp: .rightDrag
        default: .leftDrag
        }
    }

    private func begin(_ match: (mode: GestureMode, binding: GestureBinding), at point: CGPoint) {
        active = match
        windowOperator.begin(mode: match.mode, at: point)
    }

    private func end() {
        active = nil
        windowOperator.end()
    }
}
