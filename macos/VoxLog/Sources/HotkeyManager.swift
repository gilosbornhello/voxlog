import Carbon
import Cocoa
import Foundation

/// Manages global hotkey (Option key by default) for push-to-talk recording.
/// Requires Input Monitoring permission in System Settings > Privacy > Input Monitoring.
final class HotkeyManager {
    var onRecordStart: (() -> Void)?
    var onRecordStop: (() -> Void)?

    private var eventMonitor: Any?
    private var isKeyDown = false
    // Using Right Option key (keyCode 61) as default — less likely to conflict
    private let triggerKeyCode: UInt16 = 61

    func register() {
        // Check accessibility permission
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            print("[VoxLog] Requesting accessibility permission...")
            return
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .keyUp]
        ) { [weak self] event in
            self?.handleEvent(event)
        }
        print("[VoxLog] Hotkey registered (Right Option key)")
    }

    func unregister() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isKeyDown = false
    }

    private func handleEvent(_ event: NSEvent) {
        // Detect Right Option key press/release via flagsChanged
        if event.type == .flagsChanged && event.keyCode == triggerKeyCode {
            let optionPressed = event.modifierFlags.contains(.option)
            if optionPressed && !isKeyDown {
                isKeyDown = true
                onRecordStart?()
            } else if !optionPressed && isKeyDown {
                isKeyDown = false
                onRecordStop?()
            }
        }
    }
}
