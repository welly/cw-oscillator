#if os(macOS)
import AppKit
import OscillatorCore
import SwiftUI

/// The menu bar icon, shown while background keying is on: a dah and a dit that fill in
/// while the key is down, so you can see the app is running and hearing the paddle.
public struct MenuBarIcon: View {
    @Environment(OscillatorModel.self) private var model

    public init() {}

    public var body: some View {
        Image(nsImage: model.keyDown ? Self.lit : Self.idle)
            .accessibilityLabel("CW Training Oscillator")
    }

    private static let lit = makeImage(filled: true)
    private static let idle = makeImage(filled: false)

    private static func makeImage(filled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { _ in
            let height: CGFloat = 5
            let y = (16 - height) / 2
            let shapes = [CGRect(x: 2, y: y, width: 11, height: height),   // dah
                          CGRect(x: 15.5, y: y, width: height, height: height)] // dit
            NSColor.black.set()
            for rect in shapes {
                let inset = filled ? rect : rect.insetBy(dx: 0.75, dy: 0.75)
                let path = NSBezierPath(roundedRect: inset, xRadius: inset.height / 2, yRadius: inset.height / 2)
                if filled {
                    path.fill()
                } else {
                    path.lineWidth = 1.5
                    path.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// The menu bar menu: the speed settings, and a way back to the window or to quit.
public struct MenuBarMenu: View {
    @Environment(OscillatorModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        Text(status)
        Divider()
        Button("Show Window") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit CW Training Oscillator") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// "20 WPM · Iambic B", with "· Farnsworth 10 WPM" when it's on.
    private var status: String {
        var parts = ["\(Int(model.wpm)) WPM", model.mode.label]
        if model.timing.isFarnsworth { parts.append("Farnsworth \(Int(model.timing.effectiveWPM)) WPM") }
        return parts.joined(separator: " · ")
    }
}
#endif
