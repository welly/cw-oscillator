import AppKit

/// Reads the paddle from a VBand USB adapter, which shows up as a keyboard: the dit paddle is
/// Left Control and the dah paddle is Right Control. `[` and `]` work too (handy without a
/// paddle), except while a text field is being typed in.
///
/// Uses a local event monitor, so it only hears the paddle while the app is in front.
@MainActor
final class PaddleInput {
    var onChange: ((_ dit: Bool, _ dah: Bool) -> Void)?

    private var monitor: Any?
    private var leftControl = false
    private var rightControl = false
    private var leftBracket = false
    private var rightBracket = false

    // Device-dependent modifier bits (IOKit NX_DEVICELCTLKEYMASK / NX_DEVICERCTLKEYMASK).
    private static let leftControlMask: UInt = 0x0000_0001
    private static let rightControlMask: UInt = 0x0000_2000
    private static let leftBracketKey: UInt16 = 33
    private static let rightBracketKey: UInt16 = 30

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        releaseAll()
    }

    func releaseAll() {
        leftControl = false
        rightControl = false
        leftBracket = false
        rightBracket = false
        notify()
    }

    /// True when the event was a paddle and has been used up.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .flagsChanged:
            let raw = event.modifierFlags.rawValue
            leftControl = raw & Self.leftControlMask != 0
            rightControl = raw & Self.rightControlMask != 0
            notify()
            return false
        case .keyDown, .keyUp:
            guard event.keyCode == Self.leftBracketKey || event.keyCode == Self.rightBracketKey,
                  event.modifierFlags.intersection([.command, .option]).isEmpty,
                  !isTyping(in: event.window) else { return false }
            let down = event.type == .keyDown
            if event.keyCode == Self.leftBracketKey { leftBracket = down } else { rightBracket = down }
            if !event.isARepeat { notify() }
            return true
        default:
            return false
        }
    }

    private func isTyping(in window: NSWindow?) -> Bool {
        (window ?? NSApp.keyWindow)?.firstResponder is NSText
    }

    private func notify() {
        onChange?(leftControl || leftBracket, rightControl || rightBracket)
    }
}
