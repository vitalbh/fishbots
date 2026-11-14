import Foundation
import UIKit
import UserNotifications

/// The Mac's notifications (Push.swift there): this phone registers for them, gives its token to the Mac, and
/// answers from them, with the app closed too. The text comes sealed and the notification extension (iOS/Notify)
/// opens it with the push key, which is kept where the extension can read it (a Keychain group shared by the two).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ app: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(Notifications.categories)
        if MacLink.shared.pairing != nil { Notifications.ask() }
        return true
    }

    func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        MacLink.shared.registerPush(token.map { String(format: "%02x", $0) }.joined())
    }

    func application(_ app: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        MacLink.log("push: no token: \(error.localizedDescription)")
    }

    /// The app is open: it shows everything already (and the Mac doesn't send while it's watching).
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions { [] }

    /// A button on the notification, or the notification itself.
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void) {
        let link = MacLink.shared
        guard let sealed = r.notification.request.content.userInfo["fb"] as? String, let key = PushKey.load(),
              let m = PushSeal.open(sealed, key: key) else { done(); return }
        let fish = m["f"] as? String ?? "", source = m["s"] as? String ?? "", entity = m["e"] as? String ?? ""
        let pid = m["p"] as? Int
        func post(_ path: String, _ body: [String: Any]) {
            link.request("POST", path, body) { status, _ in
                if status != 200 { Notifications.failed(tr("O Mac não recebeu a resposta. Abra o app para tentar de novo.")) }
                done()
            }
        }
        switch r.actionIdentifier {
        case "allow", "deny":
            guard let pid else { done(); return }
            post("/permissions/\(pid)", ["decision": r.actionIdentifier])
        case "reply":
            let text = (r as? UNTextInputNotificationResponse)?.userText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { done(); return }
            // a question waiting takes it as its answer (the Mac does that on /reply too)
            post("/reply", ["source": source, "entity": entity, "text": text])
        default:
            // the notification itself: open that session's card
            link.openFish = fish
            done()
        }
    }
}

enum Notifications {
    /// Allowing needs the phone unlocked (Face ID): whoever holds it locked can't approve a command on the Mac.
    static var categories: Set<UNNotificationCategory> {
        let allow = UNNotificationAction(identifier: "allow", title: tr("Permitir"), options: [.authenticationRequired])
        let deny = UNNotificationAction(identifier: "deny", title: tr("Negar"), options: [.destructive, .authenticationRequired])
        let reply = UNTextInputNotificationAction(identifier: "reply", title: tr("Responder"), options: [.authenticationRequired],
                                                  textInputButtonTitle: tr("Enviar"), textInputPlaceholder: tr("Escreva para a sessão"))
        return [UNNotificationCategory(identifier: "permission", actions: [allow, deny], intentIdentifiers: []),
                UNNotificationCategory(identifier: "question", actions: [reply], intentIdentifiers: []),
                UNNotificationCategory(identifier: "waiting", actions: [reply], intentIdentifiers: []),
                UNNotificationCategory(identifier: "error", actions: [reply], intentIdentifiers: []),
                UNNotificationCategory(identifier: "open", actions: [], intentIdentifiers: []),
                UNNotificationCategory(identifier: "test", actions: [], intentIdentifiers: [])]
    }

    /// Asks once to show notifications; then gets the token (it changes: the Mac gets the current one each time).
    static func ask() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive]) { ok, _ in
            guard ok else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    static func failed(_ text: String) {
        let c = UNMutableNotificationContent()
        c.title = "Fishbots"
        c.body = text
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "failed", content: c, trigger: nil))
    }
}
