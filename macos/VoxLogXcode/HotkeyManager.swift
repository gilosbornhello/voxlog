import Carbon
import Cocoa

final class HotkeyManager {
    var onRecordStart: (() -> Void)?
    var onRecordStop: (() -> Void)?

    private var eventMonitor: Any?
    private var isKeyDown = false
    // Left Alt = Left Option (keyCode 58) on Windows 104-key keyboard
    private let triggerKeyCode: UInt16 = 58

    func register() {
        guard AXIsProcessTrusted() else {
            print("[VoxLog] Not trusted for input monitoring")
            return
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged]
        ) { [weak self] event in
            self?.handleEvent(event)
        }
        print("[VoxLog] Hotkey registered (Left Alt)")
    }

    func unregister() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isKeyDown = false
    }

    private func handleEvent(_ event: NSEvent) {
        if event.keyCode == triggerKeyCode {
            let pressed = event.modifierFlags.contains(.option)
            if pressed && !isKeyDown {
                isKeyDown = true
                onRecordStart?()
            } else if !pressed && isKeyDown {
                isKeyDown = false
                onRecordStop?()
            }
        }
    }
}
