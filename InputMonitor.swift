import Cocoa
import Carbon

class InputMonitor {

    static let shared = InputMonitor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var typedBuffer = ""
    private let maxBufferSize = 100

    private init() {}

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else {
            print("Event tap already running")
            return true
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }

                let monitor = Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleKeyEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap - permission not granted")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("Input monitoring started")
        return true
    }

    func stop() {
        guard let tap = eventTap else {
            return
        }

        CGEvent.tapEnable(tap: tap, enable: false)

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        eventTap = nil
        typedBuffer = ""

        print("Input monitoring stopped")
    }

    private func handleKeyEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        // Get the key code and characters
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Check if this is a special key (arrow keys, function keys, etc.)
        if isSpecialKey(keyCode: keyCode) {
            // Clear buffer on special keys
            typedBuffer = ""
            return Unmanaged.passRetained(event)
        }

        // Get the typed character
        guard let characters = event.keyboardGetUnicodeString() else {
            return Unmanaged.passRetained(event)
        }

        // Handle backspace
        if keyCode == 51 { // Delete/Backspace key
            if !typedBuffer.isEmpty {
                typedBuffer.removeLast()
            }
            return Unmanaged.passRetained(event)
        }

        // Add character to buffer
        typedBuffer += characters

        // Trim buffer if too long
        if typedBuffer.count > maxBufferSize {
            typedBuffer = String(typedBuffer.suffix(maxBufferSize))
        }

        // Check for matches
        if let match = ReplacementManager.shared.findMatch(in: typedBuffer) {
            print("Match found: \(match.trigger) → \(match.replacement)")

            // Prevent this keystroke from being processed
            // We'll delete the trigger and type the replacement
            DispatchQueue.main.async {
                self.performReplacement(trigger: match.trigger, replacement: match.replacement)
            }

            // Clear buffer
            typedBuffer = ""

            // Suppress the last typed character since we're replacing it
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    private func isSpecialKey(keyCode: Int64) -> Bool {
        // Arrow keys, function keys, command, option, control, shift, etc.
        let specialKeys: Set<Int64> = [
            123, 124, 125, 126, // Arrow keys
            122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, // Function keys
            53, // Escape
            48, // Tab
            36, // Return
            49, // Space (we want to keep space for our buffer)
            71, // Clear
            76, // Enter
            117, 119, 121, // Delete, End, Page Down
        ]

        return specialKeys.contains(keyCode)
    }

    private func performReplacement(trigger: String, replacement: String) {
        // Delete the trigger text
        for _ in 0..<trigger.count {
            pressKey(keyCode: 51) // Backspace
            usleep(5000) // 5ms delay between keystrokes
        }

        // Type the replacement text
        typeText(replacement)
    }

    private func pressKey(keyCode: Int64) {
        if let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true) {
            keyDownEvent.post(tap: .cghidEventTap)
        }

        if let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false) {
            keyUpEvent.post(tap: .cghidEventTap)
        }
    }

    private func typeText(_ text: String) {
        for char in text {
            if let keyCode = getKeyCode(for: char) {
                let needsShift = char.isUppercase || "!@#$%^&*()_+{}|:\"<>?".contains(char)

                if needsShift {
                    // Press shift
                    if let shiftDown = CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: true) {
                        shiftDown.post(tap: .cghidEventTap)
                    }
                }

                pressKey(keyCode: keyCode)
                usleep(10000) // 10ms delay between characters

                if needsShift {
                    // Release shift
                    if let shiftUp = CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: false) {
                        shiftUp.post(tap: .cghidEventTap)
                    }
                }
            } else {
                // For characters we can't map, use the pasteboard method
                typeCharacterViaPasteboard(char)
            }
        }
    }

    private func typeCharacterViaPasteboard(_ char: Character) {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(String(char), forType: .string)

        // Simulate Cmd+V
        let cmdDown = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)

        let vDown = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)

        usleep(10000)

        let vUp = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cghidEventTap)

        let cmdUp = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: false)
        cmdUp?.post(tap: .cghidEventTap)

        // Restore old clipboard contents
        usleep(50000)
        if let oldContents = oldContents {
            pasteboard.clearContents()
            pasteboard.setString(oldContents, forType: .string)
        }
    }

    private func getKeyCode(for character: Character) -> Int64? {
        let lowercaseChar = character.lowercased().first ?? character

        let keyMap: [Character: Int64] = [
            "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4,
            "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31,
            "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9,
            "w": 13, "x": 7, "y": 16, "z": 6,
            "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
            "6": 22, "7": 26, "8": 28, "9": 25,
            " ": 49, "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42,
            ";": 41, "'": 39, ",": 43, ".": 47, "/": 44, "`": 50
        ]

        return keyMap[lowercaseChar]
    }
}

extension CGEvent {
    func keyboardGetUnicodeString() -> String? {
        let maxLength = 4
        var actualLength = 0
        var unicodeString = [UniChar](repeating: 0, count: maxLength)

        keyboardGetUnicodeString(maxStringLength: maxLength, actualStringLength: &actualLength, unicodeString: &unicodeString)

        return String(utf16CodeUnits: unicodeString, count: actualLength)
    }
}
