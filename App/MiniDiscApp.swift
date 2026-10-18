import SwiftUI

@main
struct MiniDiscApp: App {
    @State private var store = DiscStore()

    var body: some Scene {
        Window("MiniDisc", id: "main") {
            ContentView(store: store)
                .task { await store.connect() }
                .onOpenURL { url in Task { await store.add([url]) } }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MiniDisc") { NSApp.orderFrontStandardAboutPanel(options: [.credits: credits]) }
            }
        }
    }

    /// The point of this app is a native interface on other people's work: say so up front.
    private var credits: NSAttributedString {
        NSAttributedString(string: """
            A native macOS interface for NetMD, built on:
            netmd-js (cybercase), netmd-exploits and Web MiniDisc Pro (asivery): GPL-2.0
            atrac-encoder (kai-h): MIT
            Keystone: GPL-2.0 · buffer (feross): MIT

            Our code is MIT; this app as distributed is GPL-2.0.
            Source: github.com/cpmpercussion/swift-minidisc
            """, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
    }
}
