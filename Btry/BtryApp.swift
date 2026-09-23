import SwiftUI

@main
struct BtryApp: App {
    @State private var spike = SpikeController()

    var body: some Scene {
        MenuBarExtra("Btry", systemImage: "keyboard") {
            Text(spike.status)
            Divider()
            Button("終了") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
