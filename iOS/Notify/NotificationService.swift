import UserNotifications

/// Opens the Mac's notification before it shows: the sealed part (PushSeal) becomes its title and text. If it can't
/// (no key: paired again on another Mac), the notification shows as Apple carried it ("A session needs you").
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest, withContentHandler done: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else { done(request.content); return }
        let sealed = PushKey.sealed(in: content.userInfo)
        if let sealed, let key = PushKey.load(), let m = PushSeal.open(sealed, key: key) {
            if let t = m["t"] as? String { content.title = t }
            if let b = m["b"] as? String { content.body = b }
            if let options = m["o"] as? [String], !options.isEmpty {
                content.body += "\n" + options.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "  ")
            }
            if let f = m["f"] as? String { content.threadIdentifier = f }
            // through iCloud the category (its buttons) comes inside the sealed text
            if let k = m["k"] as? String { content.categoryIdentifier = k }
        }
        done(content)
    }
}
