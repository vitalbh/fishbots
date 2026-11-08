import AppKit
import UserNotifications

/// How much each thing is allowed to call for you.
enum Level: String, Comparable {
    case ambient, attention, urgent
    private var order: Int { self == .ambient ? 0 : self == .attention ? 1 : 2 }
    static func < (a: Level, b: Level) -> Bool { a.order < b.order }
}

/// Attention rules by "source:state" (with * matching any).
/// Order: default < menu < ~/Library/Application Support/Fishbots/config.json ("attention").
enum Attention {
    static let defaults: [String: Level] = [
        "*:waiting": .attention, "*:error": .attention, "*:alert": .attention,
        // a PR with broken CI tends to stay that way for days: just the color, no dissonance
        "github:error": .ambient,
    ]

    private static let defKey = "attention"
    private static let focusKey = "focus"
    private(set) static var fromFile: [String: Level] = [:]

    static var configURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fishbots/config.json")
    }

    static var fromMenu: [String: Level] {
        let raw = UserDefaults.standard.dictionary(forKey: defKey) as? [String: String] ?? [:]
        return raw.compactMapValues(Level.init(rawValue:))
    }

    static func level(_ source: String, _ e: State) -> Level {
        let rules = defaults.merging(fromMenu) { $1 }.merging(fromFile) { $1 }
        return rules["\(source):\(e.rawValue)"] ?? rules["*:\(e.rawValue)"] ?? rules["\(source):*"] ?? .ambient
    }

    static func setLevel(_ projectKey: String, _ n: Level) {
        var raw = UserDefaults.standard.dictionary(forKey: defKey) as? [String: String] ?? [:]
        raw[projectKey] = n.rawValue
        UserDefaults.standard.set(raw, forKey: defKey)
    }

    /// Removes one of your rules (set in the app).
    static func removeRule(_ projectKey: String) {
        var raw = UserDefaults.standard.dictionary(forKey: defKey) as? [String: String] ?? [:]
        raw[projectKey] = nil
        UserDefaults.standard.set(raw, forKey: defKey)
    }

    static var focus: Bool {
        get { UserDefaults.standard.bool(forKey: focusKey) }
        set { UserDefaults.standard.set(newValue, forKey: focusKey) }
    }

    /// Reads config.json, if it exists. Format: {"attention": {"claude-code:waiting": "urgent", "github:*": "ambient"}}
    /// (the Portuguese format of older versions, {"atencao": {"claude-code:esperando": "urgente"}}, still works).
    /// The same file holds the webhooks and the fish menu actions (see Outputs.swift).
    static func reload() {
        let obj = (try? Data(contentsOf: configURL)).flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
        let at = (obj["attention"] ?? obj["atencao"]) as? [String: String] ?? [:]
        fromFile = Migration.attentionRules(at).compactMapValues(Level.init(rawValue:))
        Outputs.reload(obj)
        FishActions.reload(obj)
    }

    /// Creates config.json with an example (if it doesn't exist) and opens it.
    static func openConfig() {
        let fm = FileManager.default
        try? fm.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: configURL.path) {
            let example = """
            {
              "attention": {
                "*:waiting": "attention",
                "*:error": "attention",
                "claude-code:waiting": "urgent",
                "github:*": "ambient"
              }
            }

            """
            try? example.write(to: configURL, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(configURL)
    }
}

/// macOS notifications for the urgent level. Clicking the notification takes you to the fish.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var go: ((String) -> Void)?
    /// Permitir/Negar (Allow/Deny) buttons on a permission request notification.
    var decide: ((Int, String) -> Void)?
    private var asked = false
    /// Only exists inside the .app (outside a bundle, UNUserNotificationCenter crashes the process).
    private lazy var central: UNUserNotificationCenter? = {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        Self.categories(c)
        return c
    }()

    /// The Permitir/Negar buttons, in the current language (registered again when it changes).
    private static func categories(_ c: UNUserNotificationCenter) {
        let allow = UNNotificationAction(identifier: "allow", title: tr("Permitir"), options: [])
        let deny = UNNotificationAction(identifier: "deny", title: tr("Negar"), options: [.destructive])
        c.setNotificationCategories([UNNotificationCategory(identifier: "permission", actions: [allow, deny], intentIdentifiers: [])])
    }
    func languageChanged() { if let central { Self.categories(central) } }

    /// The notification permission, as last read ("authorized", "denied", "notDetermined"…), for /state.
    private(set) var permission = "unknown"

    /// Asks for the permission when the app opens (asking on the first notice lost that notice while macOS waited).
    func prepare() {
        guard let central else { permission = "no bundle"; return }
        asked = true
        central.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in self?.readPermission() }
    }

    func readPermission() {
        central?.getNotificationSettings { [weak self] s in
            let names: [UNAuthorizationStatus: String] = [.authorized: "authorized", .denied: "denied", .notDetermined: "notDetermined",
                                                          .provisional: "provisional"]
            DispatchQueue.main.async { self?.permission = names[s.authorizationStatus] ?? "unknown" }
        }
    }

    func notify(_ f: Fish, request: Int? = nil, summary: String? = nil) {
        NSApp.requestUserAttention(.informationalRequest)
        guard let central else { return }
        if !asked {
            asked = true
            central.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let c = UNMutableNotificationContent()
        switch f.state {
        case .waiting: c.title = tr("%@ está esperando você", f.label)
        case .error: c.title = tr("%@: erro", f.label)
        case .alert: c.title = tr("%@: alerta", f.label)
        case .done: c.title = tr("%@ terminou", f.label)
        default: c.title = "\(f.label): \(f.stateLabel)"
        }
        c.body = [f.displayTitle, f.sub].compactMap { $0 }.joined(separator: " · ")
        c.userInfo = ["fish": f.id]
        if let request {
            c.categoryIdentifier = "permission"
            c.userInfo["request"] = request
            if let summary { c.body = summary }
        }
        // one notice per fish: the new one replaces the old one
        central.add(UNNotificationRequest(identifier: f.id, content: c, trigger: nil))
    }

    func clear(_ f: Fish) {
        central?.removeDeliveredNotifications(withIdentifiers: [f.id])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let request = info["request"] as? Int, ["allow", "deny"].contains(response.actionIdentifier) {
            let action = response.actionIdentifier
            DispatchQueue.main.async { self.decide?(request, action) }
        } else if let id = info["fish"] as? String {
            DispatchQueue.main.async { self.go?(id) }
        }
        done()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}
