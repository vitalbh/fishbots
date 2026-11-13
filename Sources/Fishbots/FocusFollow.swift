import Foundation

/// A macOS Focus (Do Not Disturb, Work, Sleep…) turns the aquarium's focus mode on, and off again when it ends. Only
/// the focus mode it turned on itself goes off: one you turned on by hand stays. The active Focuses are read from
/// ~/Library/DoNotDisturb/DB/Assertions.json (by hand, from Control Center or on a schedule) every 15 s; when the
/// file can't be read (macOS may keep it private), nothing happens. Preferências → Atenção, on by default.
final class FocusFollow {
    static var enabled: Bool {
        get { UserDefaults.standard.flag("followMacFocus") }
        set { UserDefaults.standard.set(newValue, forKey: "followMacFocus") }
    }

    /// The aquarium's focus mode changed here (the menus show it).
    var changed: () -> Void = {}
    private var timer: Timer?
    /// The focus mode on now was turned on here (kept across restarts, so it still goes off when the Focus ends).
    private var turnedOn: Bool {
        get { UserDefaults.standard.bool(forKey: "focusFromMac") }
        set { UserDefaults.standard.set(newValue, forKey: "focusFromMac") }
    }

    func start() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.check() }
    }

    func check() {
        guard Self.enabled, let on = Self.macFocusOn() else { return }
        if on && !turnedOn && !Attention.focus {
            Attention.focus = true
            turnedOn = true
            changed()
        } else if !on && turnedOn {
            turnedOn = false
            if Attention.focus { Attention.focus = false; changed() }
        }
    }

    /// A Focus is on now (nil: can't tell).
    static func macFocusOn() -> Bool? {
        // the real home (a Focus is the Mac's, not this app's: even with a test home, CFFIXED_USER_HOME)
        let home = getpwuid(getuid()).flatMap { String(validatingUTF8: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let url = URL(fileURLWithPath: home).appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        guard let d = try? Data(contentsOf: url), let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let data = json["data"] as? [[String: Any]] else { return nil }
        let now = Date().timeIntervalSinceReferenceDate
        return data.contains { entry in
            (entry["storeAssertionRecords"] as? [[String: Any]] ?? []).contains { r in
                // one with an end that already passed is over
                guard let end = (r["assertionDetails"] as? [String: Any])?["assertionDetailsUserVisibleEndDate"] as? Double else { return true }
                return end > now
            }
        }
    }
}
