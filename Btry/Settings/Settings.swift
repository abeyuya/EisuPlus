import CoreGraphics
import Foundation

enum Modifier: String, Codable, CaseIterable, Sendable {
    case control, option, command, shift, function

    var flag: CGEventFlags {
        switch self {
        case .control: .maskControl
        case .option: .maskAlternate
        case .command: .maskCommand
        case .shift: .maskShift
        case .function: .maskSecondaryFn
        }
    }
}

enum Trigger: String, Codable, CaseIterable, Sendable {
    /// 修飾キーを押したままマウスを動かす（クリック不要）
    case mouseMove
    case leftDrag
    case rightDrag
}

struct GestureBinding: Codable, Equatable, Sendable {
    var modifiers: Set<Modifier>
    var trigger: Trigger

    var flags: CGEventFlags {
        modifiers.reduce(into: CGEventFlags()) { $0.insert($1.flag) }
    }
}

enum GestureMode: String, Codable, Sendable {
    case move, resize
}

struct Settings: Codable, Equatable, Sendable {
    var isPaused = false
    var inputSourceSwitchEnabled = true
    var moveEnabled = true
    var moveBinding = GestureBinding(modifiers: [.control], trigger: .mouseMove)
    var resizeEnabled = true
    var resizeBinding = GestureBinding(modifiers: [.control, .option], trigger: .mouseMove)

    /// 有効なジェスチャのバインド一覧
    var activeBindings: [(mode: GestureMode, binding: GestureBinding)] {
        guard !isPaused else { return [] }
        var result: [(GestureMode, GestureBinding)] = []
        if moveEnabled { result.append((.move, moveBinding)) }
        if resizeEnabled { result.append((.resize, resizeBinding)) }
        return result
    }
}

extension CGEventFlags {
    /// ジェスチャ判定に使う修飾キー（デバイス依存ビットや NonCoalesced などを除く）
    static let gestureModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift, .maskSecondaryFn]

    var gestureModifiers: CGEventFlags { intersection(.gestureModifiers) }
}
