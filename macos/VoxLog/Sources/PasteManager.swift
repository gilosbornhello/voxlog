import AppKit
import Foundation

/// Pastes text into the frontmost app via Cmd+V, then restores the previous clipboard.
final class PasteManager {

    func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Save current clipboard
        let previousContents = pasteboard.pasteboardItems?.compactMap { item -> (String, Data)? in
            guard let type = item.types.first,
                  let data = item.data(forType: type) else { return nil }
            return (type.rawValue, data)
        }

        // Set new text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        simulatePaste()

        // Restore previous clipboard after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let previous = previousContents, !previous.isEmpty {
                pasteboard.clearContents()
                for (typeStr, data) in previous {
                    let type = NSPasteboard.PasteboardType(typeStr)
                    pasteboard.setData(data, forType: type)
                }
            }
        }
    }

    private func simulatePaste() {
        // Cmd+V keydown
        let vKeyCode: CGKeyCode = 0x09 // 'v' key
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
