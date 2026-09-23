import AppKit

/// スナップ先を示す半透明のオーバーレイ
@MainActor
final class SnapPreviewWindow {
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        view.layer?.borderWidth = 2
        view.layer?.cornerRadius = 10
        panel.contentView = view
        return panel
    }()

    /// frame はグローバル座標（左上原点）
    func show(_ frame: CGRect) {
        panel.setFrame(CoordinateConverter.toAppKit(frame).insetBy(dx: 4, dy: 4), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}
