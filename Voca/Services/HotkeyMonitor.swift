import Cocoa

class HotkeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private let onRecordStart: () -> Void
    private let onRecordStop: () -> Void
    private let onHistoryPaste: () -> Void

    private var isRecordingAudio = false

    // Hold-to-record state
    private var isModifierHeld = false

    // Double-tap detection state
    private var lastTapTime: Date?
    private var tapCount = 0
    private let doubleTapThreshold: TimeInterval = 0.3

    // History hotkey: Ctrl+Option+V
    private let historyKeyCode: UInt16 = 0x09  // V
    private let historyModifiers: NSEvent.ModifierFlags = [.control, .option]

    init(onRecordStart: @escaping () -> Void,
         onRecordStop: @escaping () -> Void,
         onHistoryPaste: @escaping () -> Void) {
        self.onRecordStart = onRecordStart
        self.onRecordStop = onRecordStop
        self.onHistoryPaste = onHistoryPaste

        startMonitoring()
    }

    private func startMonitoring() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .keyUp]
        ) { [weak self] event in
            self?.handleEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .keyUp]
        ) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
    }

    private func handleEvent(_ event: NSEvent) {
        // Check for history hotkey (Ctrl+Option+V)
        if event.type == .keyDown {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == historyKeyCode && flags == historyModifiers {
                onHistoryPaste()
                return
            }
        }

        // Handle recording hotkey
        let hotkey = AppSettings.shared.recordHotkey
        if hotkey.isDoubleTap {
            handleDoubleTapToRecord(event)
        } else {
            handleHoldToRecord(event)
        }
    }

    private func handleHoldToRecord(_ event: NSEvent) {
        guard event.type == .flagsChanged else { return }

        let hotkey = AppSettings.shared.recordHotkey
        let requiredModifiers = NSEvent.ModifierFlags(rawValue: hotkey.modifiers)
        let currentFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Check if exactly the required modifiers are pressed
        let modifiersMatch = currentFlags == requiredModifiers

        // Modifiers pressed - start recording
        if modifiersMatch && !isModifierHeld {
            isModifierHeld = true
            if !isRecordingAudio {
                isRecordingAudio = true
                onRecordStart()
            }
        }
        // Modifiers released - stop recording
        else if !modifiersMatch && isModifierHeld {
            isModifierHeld = false
            if isRecordingAudio {
                isRecordingAudio = false
                onRecordStop()
            }
        }
    }

    private func handleDoubleTapToRecord(_ event: NSEvent) {
        guard event.type == .flagsChanged else { return }

        let hotkey = AppSettings.shared.recordHotkey
        let requiredModifiers = NSEvent.ModifierFlags(rawValue: hotkey.modifiers)
        let currentFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Check if the required modifier is pressed (allows other modifiers too)
        let modifierPressed = currentFlags.contains(requiredModifiers)

        // Modifier key pressed
        if modifierPressed && !isModifierHeld {
            isModifierHeld = true
            let now = Date()

            if let lastTap = lastTapTime,
               now.timeIntervalSince(lastTap) < doubleTapThreshold {
                // Double-tap detected - start recording
                tapCount = 2
                if !isRecordingAudio {
                    isRecordingAudio = true
                    onRecordStart()
                }
            } else {
                // First tap
                tapCount = 1
                lastTapTime = now
            }
        }
        // Modifier key released
        else if !modifierPressed && isModifierHeld {
            isModifierHeld = false

            // If we were recording, stop
            if isRecordingAudio {
                isRecordingAudio = false
                onRecordStop()
                tapCount = 0
                lastTapTime = nil
            }
        }
    }

    deinit {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
