import os

/// `log stream --predicate 'subsystem == "com.github.abeyuya.EisuMod"' --level info` で確認できる。
enum Log {
    static let app = Logger(subsystem: "com.github.abeyuya.EisuMod", category: "app")
    static let tap = Logger(subsystem: "com.github.abeyuya.EisuMod", category: "tap")
    static let input = Logger(subsystem: "com.github.abeyuya.EisuMod", category: "input")
    static let window = Logger(subsystem: "com.github.abeyuya.EisuMod", category: "window")
}
