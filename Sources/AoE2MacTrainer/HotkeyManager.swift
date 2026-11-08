import Carbon
import Foundation

enum TrainerHotkey: UInt32 {
    case nextStep = 1
    case previousStep = 2
    case cycleBuild = 3
    case toggleClock = 4
    case toggleOverlay = 5
    case reset = 6
}

/// Carbon hotkeys work while AoE2 is focused without keyboard-event monitoring.
final class HotkeyManager {
    private var eventHandler: EventHandlerRef?
    private var hotkeys: [EventHotKeyRef] = []
    private let onHotkey: (TrainerHotkey) -> Void

    init(onHotkey: @escaping (TrainerHotkey) -> Void) {
        self.onHotkey = onHotkey

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var eventID = EventHotKeyID(signature: 0, id: 0)
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &eventID
            )
            guard status == noErr,
                  eventID.signature == 0x41324D54,
                  let action = TrainerHotkey(rawValue: eventID.id) else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue()
            manager.onHotkey(action)
            return noErr
        }
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            context,
            &eventHandler
        )
        guard status == noErr else { return }

        let bindings: [(TrainerHotkey, UInt32)] = [
            (.nextStep, UInt32(kVK_ANSI_N)),
            (.previousStep, UInt32(kVK_ANSI_P)),
            (.cycleBuild, UInt32(kVK_ANSI_B)),
            (.toggleClock, UInt32(kVK_ANSI_S)),
            (.toggleOverlay, UInt32(kVK_ANSI_H)),
            (.reset, UInt32(kVK_ANSI_R))
        ]

        for (action, keyCode) in bindings {
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: 0x41324D54, id: action.rawValue)
            let result = RegisterEventHotKey(
                keyCode,
                UInt32(controlKey | optionKey),
                identifier,
                GetApplicationEventTarget(),
                0,
                &reference
            )
            if result == noErr, let reference { hotkeys.append(reference) }
        }
    }

    deinit {
        for reference in hotkeys { UnregisterEventHotKey(reference) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
