import Carbon
import Foundation

/// A global keyboard shortcut (works in any app, no Accessibility permission: Carbon's hot keys).
/// ⌃⌥F: go to the session that has been waiting for you the longest.
final class Hotkey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static var all: [UInt32: Hotkey] = [:]

    init?(keyCode: UInt32, modifiers: UInt32, id: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if let h = Hotkey.all[hk.id] { DispatchQueue.main.async { h.action() } }
            return noErr
        }, 1, &spec, nil, &handler)
        guard status == noErr else { return nil }
        let hkID = EventHotKeyID(signature: OSType(0x46_49_53_48), id: id)   // "FISH"
        guard RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref) == noErr else { return nil }
        Hotkey.all[id] = self
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// ⌃⌥F ("fish"; ⌃⌥Space would clash with the Mac's input source switch).
    static func waitingLongest(_ action: @escaping () -> Void) -> Hotkey? {
        Hotkey(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(controlKey | optionKey), id: 1, action: action)
    }
}
