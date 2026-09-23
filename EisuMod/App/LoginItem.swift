import Observation
import ServiceManagement

/// ログイン時に起動するかどうか。状態はシステム側（ログイン項目）が持つ。
@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    private(set) var errorMessage: String?

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            Log.app.error("login item update failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
