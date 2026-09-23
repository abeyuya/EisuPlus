import Foundation

enum SnapZone: Equatable, Sendable {
    case leftHalf, rightHalf
}

/// 画面端の判定とスナップ先の計算、スナップ前のサイズの記録を行う。WindowOperator のキュー上でのみ使う。
final class SnapController {
    private static let edgeThreshold: CGFloat = 5
    private static let frameTolerance: CGFloat = 2
    private static let maxRecords = 32

    private let geometry: ScreenGeometry

    /// スナップしたウィンドウと、スナップ前のサイズ・スナップ後のフレーム
    private var records: [(window: WindowHandle, originalSize: CGSize, snappedFrame: CGRect)] = []

    init(geometry: ScreenGeometry) {
        self.geometry = geometry
    }

    /// カーソルがスナップ領域にあれば、その領域とスナップ先のフレームを返す
    func zone(at point: CGPoint) -> (zone: SnapZone, frame: CGRect)? {
        let screens = geometry.screens
        guard let screen = screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }) else { return nil }
        let frame = screen.frame
        let visible = screen.visibleFrame

        // 隣のディスプレイと接している辺は、カーソルがそのまま抜けるので端とみなさない
        func hasNeighbor(where touches: (CGRect) -> Bool) -> Bool {
            screens.contains { touches($0.frame) && ($0.frame.minY...$0.frame.maxY).contains(point.y) }
        }

        let half = visible.width / 2
        if point.x <= frame.minX + Self.edgeThreshold, !hasNeighbor(where: { abs($0.maxX - frame.minX) < 1 }) {
            return (.leftHalf, CGRect(x: visible.minX, y: visible.minY, width: half, height: visible.height))
        }
        if point.x >= frame.maxX - Self.edgeThreshold - 1, !hasNeighbor(where: { abs($0.minX - frame.maxX) < 1 }) {
            return (.rightHalf, CGRect(x: visible.minX + half, y: visible.minY, width: visible.width - half, height: visible.height))
        }
        return nil
    }

    /// スナップを確定する。スナップ前のサイズを記録しておく
    func apply(_ frame: CGRect, to window: WindowHandle, originalSize: CGSize) {
        // 一度解除して再スナップした場合でも、元のサイズを保持する
        let original = takeRecord(for: window)?.originalSize ?? originalSize
        // 移動先ディスプレイの大きさでサイズが制限されることがあるので、サイズ → 位置 → サイズの順に設定する
        window.setSize(frame.size)
        window.setPosition(frame.origin)
        window.setSize(frame.size)

        records.append((window, original, frame))
        if records.count > Self.maxRecords { records.removeFirst(records.count - Self.maxRecords) }
    }

    /// スナップしたままのウィンドウなら記録を取り出してスナップ前のサイズを返す
    func unsnapSize(for window: WindowHandle, currentFrame: CGRect) -> CGSize? {
        guard let record = takeRecord(for: window),
              // スナップ後にユーザーが自分でサイズを変えていたら元に戻さない
              Self.isApproximatelyEqual(record.snappedFrame, currentFrame) else { return nil }
        return record.originalSize
    }

    private func takeRecord(for window: WindowHandle) -> (window: WindowHandle, originalSize: CGSize, snappedFrame: CGRect)? {
        guard let index = records.firstIndex(where: { $0.window.isSame(as: window) }) else { return nil }
        return records.remove(at: index)
    }

    private static func isApproximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= frameTolerance && abs(a.minY - b.minY) <= frameTolerance
            && abs(a.width - b.width) <= frameTolerance && abs(a.height - b.height) <= frameTolerance
    }
}
