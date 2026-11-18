#if os(macOS)
import AppKit
import IOKit.hid

/// Reads a VBand paddle adapter straight from USB, so the paddle keys the oscillator whichever
/// app is in front. Only the adapter is matched, so Control on your keyboard is left alone.
///
/// Needs Input Monitoring permission (System Settings › Privacy & Security). The device is
/// shared, so its Control presses still reach the app in front as well.
@MainActor
final class HIDPaddle {
    enum Access { case granted, denied, unknown }

    var onChange: ((_ dit: Bool, _ dah: Bool) -> Void)?
    private(set) var dit = false
    private(set) var dah = false
    /// Always false now: the adapter is never opened exclusively.
    private(set) var exclusive = false

    private var manager: IOHIDManager?

    /// VBand USB paddle adapter ("PaddleAdapter", Microchip vendor ID). Match on these IDs only:
    /// a product-name key isn't matchable and silently matches every HID device, mouse included.
    nonisolated private static let vendorID = 0x04D8
    nonisolated private static let productID = 0x01A6
    private static let keyboardPage: UInt32 = 0x07
    private static let leftControl: UInt32 = 0xE0
    private static let rightControl: UInt32 = 0xE4

    static var access: Access {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .denied
        default: .unknown
        }
    }

    /// Asks for Input Monitoring (macOS shows its prompt the first time only).
    static func requestAccess() -> Bool { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    var isRunning: Bool { manager != nil }

    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: Self.vendorID, kIOHIDProductIDKey: Self.productID,
        ] as CFDictionary)
        // Belt and braces: never open anything but the adapter.
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        guard devices.allSatisfy(Self.isAdapter) else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let paddle = Unmanaged<HIDPaddle>.fromOpaque(context).takeUnretainedValue()
            let element = IOHIDValueGetElement(value)
            guard HIDPaddle.isAdapter(IOHIDElementGetDevice(element)) else { return }
            let page = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            let down = IOHIDValueGetIntegerValue(value) != 0
            // Scheduled on the main run loop, so this is the main thread.
            MainActor.assumeIsolated { paddle.handle(page: page, usage: usage, down: down) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let paddle = Unmanaged<HIDPaddle>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { paddle.release() }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        // Shared, never seized: seizing a keyboard device can upset the rest of the input system.
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
    }

    nonisolated static func isAdapter(_ device: IOHIDDevice) -> Bool {
        IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int == vendorID
            && IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int == productID
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        release()
    }

    private func release() {
        guard dit || dah else { return }
        dit = false
        dah = false
        onChange?(false, false)
    }

    private func handle(page: UInt32, usage: UInt32, down: Bool) {
        guard page == Self.keyboardPage else { return }
        switch usage {
        case Self.leftControl where dit != down: dit = down
        case Self.rightControl where dah != down: dah = down
        default: return
        }
        onChange?(dit, dah)
    }
}
#endif
