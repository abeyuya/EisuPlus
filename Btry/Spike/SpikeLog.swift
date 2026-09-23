import Foundation
import os

/// スパイク用ログ。os_log に加えて ~/Library/Logs/Btry/spike.log に追記する。
enum SpikeLog {
    private static let logger = Logger(subsystem: "com.abeyuya.btry", category: "spike")
    private static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Btry", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("spike.log")
    }()

    static func write(_ message: String) {
        logger.info("\(message, privacy: .public)")
        let line = "\(Date().ISO8601Format()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: fileURL)
        }
    }
}
