import AppKit
import SwiftUI

@main
struct OscillatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = OscillatorModel()

    var body: some Scene {
        Window("CW Oscillator", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 460, minHeight: 620)
                .onAppear { model.start() }
        }
        .defaultSize(width: 520, height: 720)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Built as a bare SwiftPM executable it needs telling to be a regular app with a window.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
