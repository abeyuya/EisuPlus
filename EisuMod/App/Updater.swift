#if !APP_STORE
import Foundation
import Observation
import Sparkle

/// Sparkle による自動アップデート。appcast.xml は GitHub Pages に置く（docs/RELEASE.md）。
/// App Store 版はストアが更新するので使わない。
@MainActor
@Observable
final class Updater: NSObject {
    /// 定期確認で見つかった更新のバージョン。メニューバー常駐アプリでダイアログが他のウィンドウに隠れることがあるので、メニューにも出す
    private(set) var pendingVersion: String?
    private(set) var canCheckForUpdates = false

    var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                controller.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    // userDriverDelegate に self を渡すため、init の後半で作る
    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var observation: NSKeyValueObservation?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

// Sparkle は delegate をメインスレッドから呼ぶ
extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    // 定期確認で見つかった更新は、作業中のアプリからフォーカスを奪わずに出す
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !state.userInitiated else { return }
        pendingVersion = update.displayVersionString
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        pendingVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        pendingVersion = nil
    }
}
#endif
