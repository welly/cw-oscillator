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
                .frame(width: 520, height: 655)
                .onAppear { model.start() }
        }
        // Fixed size: the window can't be resized or zoomed.
        .windowResizability(.contentSize)
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
