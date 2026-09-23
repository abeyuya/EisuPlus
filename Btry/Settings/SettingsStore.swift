import Foundation
import Observation
import os

/// 設定の保存と、イベントタップのスレッドから読むためのスナップショットを提供する。
@MainActor
@Observable
final class SettingsStore {
    private static let defaultsKey = "settings.v1"

    var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            snapshot.set(settings)
            save()
        }
    }

    /// 任意のスレッドから読める現在値
    @ObservationIgnored let snapshot: SettingsSnapshot

    init() {
        let loaded = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
        settings = loaded
        snapshot = SettingsSnapshot(loaded)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

final class SettingsSnapshot: Sendable {
    private let lock: OSAllocatedUnfairLock<Settings>

    init(_ settings: Settings) {
        lock = OSAllocatedUnfairLock(initialState: settings)
    }

    var current: Settings { lock.withLock { $0 } }

    func set(_ settings: Settings) {
        lock.withLock { $0 = settings }
    }
}
