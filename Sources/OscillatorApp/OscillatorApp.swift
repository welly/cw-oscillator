import AppKit
import OscillatorUI
import SwiftUI

@main
struct OscillatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = OscillatorModel()

    var body: some Scene {
        Window("CW Training Oscillator", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: ContentView.minimumSize.width, minHeight: ContentView.minimumSize.height)
                .onAppear { model.start() }
        }
        .defaultSize(ContentView.minimumSize)
        // Resizable, down to the smallest size the layout fits.
        .windowResizability(.contentMinSize)
        .commands { AppCommands() }

        Window("CW Training Oscillator Help", id: "help") {
            HelpView()
                .environment(model)
                .frame(width: 480, height: 560)
        }
        .windowResizability(.contentSize)
        // Opened from the Help menu, so not listed in the Window menu as well.
        .commandsRemoved()

        Window("Statistics", id: "stats") {
            StatisticsView()
                .environment(model)
                .frame(minWidth: 480, idealWidth: 520, minHeight: 420, idealHeight: 640)
        }
        .defaultSize(width: 520, height: 640)
        .windowResizability(.contentMinSize)
        // SwiftUI lists the window in the Window menu; this gives that item ⌘I.
        .keyboardShortcut("i", modifiers: .command)

        Settings {
            SettingsView()
                .environment(model)
        }

        // While background keying is on: shows the app is running (and lights as you key),
        // and keeps it running with the window closed.
        MenuBarExtra(isInserted: Binding(get: { model.backgroundKeying },
                                         set: { if !$0 { model.backgroundKeying = false } })) {
            MenuBarMenu()
                .environment(model)
        } label: {
            MenuBarIcon()
                .environment(model)
        }
    }
}

/// Help ▸ CW Training Oscillator Help.
private struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("CW Training Oscillator Help") { openWindow(id: "help") }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Built as a bare SwiftPM executable it needs telling to be a regular app with a window.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Quits when the window closes, unless background keying is on: then it carries on in the
    /// menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: "backgroundKeying")
    }
}
