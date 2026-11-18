#if os(iOS)
import GameController

/// Reads the paddle from a VBand USB adapter plugged into the iPhone or iPad. It shows up as a
/// keyboard: the dit paddle is Left Control and the dah paddle is Right Control. `[` and `]`
/// work too, from any hardware keyboard.
///
/// Uses the GameController keyboard, which reports modifier keys going down and up on their
/// own (UIKit only sees them with another key) and doesn't need anything to have focus.
@MainActor
final class PaddleInput {
    var onChange: ((_ dit: Bool, _ dah: Bool) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var pressed: Set<GCKeyCode> = []

    private static let ditKeys: Set<GCKeyCode> = [.leftControl, .openBracket]
    private static let dahKeys: Set<GCKeyCode> = [.rightControl, .closeBracket]

    func start() {
        guard observers.isEmpty else { return }
        let centre = NotificationCenter.default
        observers.append(centre.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.attach() }
        })
        observers.append(centre.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseAll() }
        })
        attach()
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
        releaseAll()
    }

    func releaseAll() {
        pressed = []
        notify()
    }

    /// Every connected keyboard is merged into the coalesced one.
    private func attach() {
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = { [weak self] _, _, keyCode, down in
            // Called on the main queue (the default handler queue).
            MainActor.assumeIsolated { self?.key(keyCode, down: down) }
        }
    }

    private func key(_ code: GCKeyCode, down: Bool) {
        guard Self.ditKeys.contains(code) || Self.dahKeys.contains(code) else { return }
        let changed = down ? pressed.insert(code).inserted : pressed.remove(code) != nil
        if changed { notify() }
    }

    private func notify() {
        onChange?(!pressed.isDisjoint(with: Self.ditKeys), !pressed.isDisjoint(with: Self.dahKeys))
    }
}
#endif
