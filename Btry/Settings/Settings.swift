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
    var resizeBinding = GestureBinding(modifiers: [.option], trigger: .mouseMove)
    var snapEnabled = true
    /// ウィンドウの移動・リサイズを行わないアプリ
    var excludedBundleIDs: Set<String> = []

    /// 有効なジェスチャのバインド一覧
    var activeBindings: [(mode: GestureMode, binding: GestureBinding)] {
        guard !isPaused else { return [] }
        var result: [(GestureMode, GestureBinding)] = []
        // 修飾キーが空だとマウスを動かすだけで発動してしまうので無効扱いにする
        if moveEnabled, !moveBinding.modifiers.isEmpty { result.append((.move, moveBinding)) }
        if resizeEnabled, !resizeBinding.modifiers.isEmpty { result.append((.resize, resizeBinding)) }
        return result
    }
}

extension Settings {
    /// 項目が欠けていてもデフォルト値で補う（項目を追加しても保存済みの設定が消えないように）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        isPaused = try c.decodeIfPresent(Bool.self, forKey: .isPaused) ?? d.isPaused
        inputSourceSwitchEnabled = try c.decodeIfPresent(Bool.self, forKey: .inputSourceSwitchEnabled) ?? d.inputSourceSwitchEnabled
        moveEnabled = try c.decodeIfPresent(Bool.self, forKey: .moveEnabled) ?? d.moveEnabled
        moveBinding = try c.decodeIfPresent(GestureBinding.self, forKey: .moveBinding) ?? d.moveBinding
        resizeEnabled = try c.decodeIfPresent(Bool.self, forKey: .resizeEnabled) ?? d.resizeEnabled
        resizeBinding = try c.decodeIfPresent(GestureBinding.self, forKey: .resizeBinding) ?? d.resizeBinding
        snapEnabled = try c.decodeIfPresent(Bool.self, forKey: .snapEnabled) ?? d.snapEnabled
        excludedBundleIDs = try c.decodeIfPresent(Set<String>.self, forKey: .excludedBundleIDs) ?? d.excludedBundleIDs
    }
}

extension CGEventFlags {
    /// ジェスチャ判定に使う修飾キー（デバイス依存ビットや NonCoalesced などを除く）
    static let gestureModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift, .maskSecondaryFn]

    var gestureModifiers: CGEventFlags { intersection(.gestureModifiers) }
}
