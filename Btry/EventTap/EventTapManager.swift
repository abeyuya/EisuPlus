@preconcurrency import CoreGraphics
import Foundation

/// イベントタップのスレッド上で呼ばれるハンドラ。状態はそのスレッドだけで触ること。
protocol EventHandler: AnyObject {
    var eventTypes: [CGEventType] { get }
    /// true を返すとイベントを握りつぶす
    func handle(type: CGEventType, event: CGEvent) -> Bool
}

/// CGEventTap を1つだけ作り、専用スレッドの RunLoop で動かして各ハンドラへ振り分ける。
final class EventTapManager: @unchecked Sendable {
    private let handlers: [EventHandler]
    private var tap: CFMachPort?
    private var thread: EventTapThread?

    init(handlers: [EventHandler]) {
        self.handlers = handlers
    }

    var isRunning: Bool { tap != nil }

    /// メインスレッドから呼ぶ。権限がないなどでタップを作れなければ false。
    @MainActor
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask = handlers.flatMap(\.eventTypes).reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.dispatch(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.tap.error("CGEvent.tapCreate failed")
            return false
        }

        let thread = EventTapThread()
        thread.start()
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(thread.runLoop, source, .commonModes)
        CFRunLoopWakeUp(thread.runLoop)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.thread = thread
        Log.tap.info("event tap started")
        return true
    }

    @MainActor
    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        thread?.stopRunLoop()
        self.tap = nil
        self.thread = nil
        Log.tap.info("event tap stopped")
    }

    private func dispatch(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.tap.notice("event tap disabled (\(type.rawValue, privacy: .public)); re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // Btry 自身が合成したイベント（隣のデスクトップへ運ぶ操作など）は判定に使わない
        if event.getIntegerValueField(.eventSourceUserData) == SpaceCarrier.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }
        var swallow = false
        for handler in handlers where handler.eventTypes.contains(type) {
            // 握りつぶす場合も全ハンドラに通知する（⌘単押しのキャンセル判定などのため）
            if handler.handle(type: type, event: event) { swallow = true }
        }
        return swallow ? nil : Unmanaged.passUnretained(event)
    }
}

/// RunLoop を回し続けるだけのスレッド
private final class EventTapThread: Thread, @unchecked Sendable {
    private let ready = DispatchSemaphore(value: 0)
    private var _runLoop: CFRunLoop?

    override init() {
        super.init()
        name = "com.abeyuya.btry.eventtap"
        qualityOfService = .userInteractive
    }

    /// start() 後に呼ぶと、RunLoop が用意できるまで待つ
    var runLoop: CFRunLoop {
        if _runLoop == nil { ready.wait() }
        return _runLoop!
    }

    override func main() {
        _runLoop = CFRunLoopGetCurrent()
        // ソースが無いと CFRunLoopRun が即座に戻るため、ダミーのポートを置いておく
        RunLoop.current.add(NSMachPort(), forMode: .common)
        ready.signal()
        CFRunLoopRun()
    }

    func stopRunLoop() {
        if let _runLoop { CFRunLoopStop(_runLoop) }
    }
}
