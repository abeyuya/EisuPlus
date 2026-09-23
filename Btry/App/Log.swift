import os

/// `log stream --predicate 'subsystem == "com.abeyuya.btry"' --level info` で確認できる。
enum Log {
    static let app = Logger(subsystem: "com.abeyuya.btry", category: "app")
    static let tap = Logger(subsystem: "com.abeyuya.btry", category: "tap")
    static let input = Logger(subsystem: "com.abeyuya.btry", category: "input")
    static let window = Logger(subsystem: "com.abeyuya.btry", category: "window")
}
