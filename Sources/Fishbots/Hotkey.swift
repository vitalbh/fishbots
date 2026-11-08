import AppKit
import Carbon

/// What the global shortcuts do, always with the session that has been waiting for you the longest.
enum HotkeyAction: String, CaseIterable {
    case go      // its terminal comes forward
    case read    // reads its question (or last reply) aloud
    case mic     // opens its card with the microphone on: speak, Enter sends

    var id: UInt32 { UInt32(Self.allCases.firstIndex(of: self)! + 1) }
    var defaultsKey: String { self == .go ? "hotkey" : "hotkey." + rawValue }
    /// ⌃⌥F ("fish"; ⌃⌥Space would clash with the Mac's input source switch), ⌃⌥R (read), ⌃⌥M (mic).
    var standard: Shortcut {
        switch self {
        case .go: return Shortcut(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(controlKey | optionKey), key: "F")
        case .read: return Shortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey | optionKey), key: "R")
        case .mic: return Shortcut(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey), key: "M")
        }
    }
    var title: String {
        switch self {
        case .go: return tr("Ir para quem espera há mais tempo")
        case .read: return tr("Ouvir a pergunta de quem espera")
        case .mic: return tr("Responder falando (abre o microfone)")
        }
    }

    var shortcut: Shortcut {
        get {
            guard let d = UserDefaults.standard.data(forKey: defaultsKey), let s = try? JSONDecoder().decode(Shortcut.self, from: d) else { return standard }
            return s
        }
        nonmutating set {
            if newValue == standard { UserDefaults.standard.removeObject(forKey: defaultsKey) }
            else if let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: defaultsKey) }
        }
    }
}

/// A global keyboard shortcut (works in any app, no Accessibility permission: Carbon's hot keys).
final class Hotkey {
    private var ref: EventHotKeyRef?
    private let action: () -> Void
    private static var all: [UInt32: Hotkey] = [:]
    private static var handler: EventHandlerRef?

    init?(_ s: Shortcut, id: UInt32, action: @escaping () -> Void) {
        self.action = action
        // one handler for every shortcut (several would each run the action)
        if Self.handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hk)
                if let h = Hotkey.all[hk.id] { DispatchQueue.main.async { h.action() } }
                return noErr
            }, 1, &spec, nil, &Self.handler)
            guard status == noErr else { return nil }
        }
        let hkID = EventHotKeyID(signature: OSType(0x46_49_53_48), id: id)   // "FISH"
        guard RegisterEventHotKey(s.keyCode, s.modifiers, hkID, GetApplicationEventTarget(), 0, &ref) == noErr else { return nil }
        Hotkey.all[id] = self
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }
}

/// A key with modifiers, stored in the settings, shown as "⌃⌥F".
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32        // Carbon's: controlKey, optionKey, shiftKey, cmdKey
    var key: String              // what to show for the key

    /// From a key press; nil without a modifier (a bare key would take that key away from every app).
    init?(event e: NSEvent) {
        var m: UInt32 = 0
        let f = e.modifierFlags
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        if f.contains(.command) { m |= UInt32(cmdKey) }
        guard m != 0 else { return nil }
        self.init(keyCode: UInt32(e.keyCode), modifiers: m, key: Shortcut.name(e))
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) { self.keyCode = keyCode; self.modifiers = modifiers; self.key = key }

    private static func name(_ e: NSEvent) -> String {
        let special: [Int: String] = [kVK_Space: tr("Espaço"), kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
                                      kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
                                      kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
                                      kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"]
        if let s = special[Int(e.keyCode)] { return s }
        return (e.charactersIgnoringModifiers ?? "?").uppercased()
    }

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + key
    }
}
