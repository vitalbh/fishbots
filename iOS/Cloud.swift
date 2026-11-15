import CloudKit
import Foundation

/// Notifications through the person's own iCloud, with no server and no push key of anyone's: the Mac writes a note
/// to the private database of the container both apps share (Sources/Fishbots/CloudNotes.swift), and this
/// subscription makes Apple notify the phone of it, in well under a second. The note carries the same sealed text as a
/// direct push (`fb`, PushSeal); the notification extension opens it the same way and sets its buttons.
///
/// Each paired device has a zone of its own (`device-<id>`), so a note sealed for this phone doesn't ring an iPad on
/// the same account. Only in builds with the container (`FishbotsCloud` in Info.plist, set by scripts/ios.sh with
/// FISHBOTS_PUSH=1 on a device).
enum Cloud {
    static let recordType = "Note"
    /// The pairing this phone is subscribed for (in this launch).
    private static var subscribed: String?

    static var container: CKContainer? {
        (Bundle.main.object(forInfoDictionaryKey: "FishbotsCloud") as? String).flatMap { $0.isEmpty ? nil : CKContainer(identifier: $0) }
    }

    static func zone(of device: String) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "device-" + device, ownerName: CKCurrentUserDefaultName)
    }

    /// The zone and the subscription for this pairing (once per launch); `ready` once Apple has them.
    static func subscribe(device: String, ready: @escaping () -> Void) {
        guard let container else { return }
        if subscribed == device { ready(); return }
        let db = container.privateCloudDatabase
        let zone = zone(of: device)
        container.accountStatus { status, error in
            guard status == .available else {
                MacLink.log("cloud: no iCloud account here (\(status.rawValue)) \(error?.localizedDescription ?? "")")
                return
            }
            db.save(CKRecordZone(zoneID: zone)) { _, error in
                if let error { MacLink.log("cloud: zone: \(error.localizedDescription)") }
                // a subscription needs its record type to exist, and in development the first record written makes it:
                // one is written and taken back, in case the Mac hasn't written any yet
                let seed = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: "seed", zoneID: zone))
                seed["fb"] = ""
                seed["sent"] = 0.0
                let op = CKModifyRecordsOperation(recordsToSave: [seed])
                op.savePolicy = .allKeys
                op.modifyRecordsResultBlock = { result in
                    if case .failure(let e) = result { MacLink.log("cloud: seed: \(e.localizedDescription)") }
                    db.delete(withRecordID: seed.recordID) { _, _ in
                        db.save(subscription(zone: zone, device: device)) { _, error in
                            if let error { MacLink.log("cloud: subscription: \(error.localizedDescription)"); return }
                            MacLink.log("cloud: subscribed")
                            DispatchQueue.main.async { subscribed = device; ready() }
                        }
                    }
                }
                db.add(op)
            }
        }
    }

    private static func subscription(zone: CKRecordZone.ID, device: String) -> CKQuerySubscription {
        let sub = CKQuerySubscription(recordType: recordType, predicate: NSPredicate(value: true),
                                      subscriptionID: "notes-" + device, options: [.firesOnRecordCreation])
        sub.zoneID = zone
        let info = CKSubscription.NotificationInfo()
        // what shows if the extension can't open it; it puts the sealed text and the buttons in its place
        info.title = "Fishbots"
        info.alertBody = tr("Uma sessão precisa de você")
        info.soundName = "default"
        info.shouldSendMutableContent = true
        info.desiredKeys = ["fb", "sent"]
        sub.notificationInfo = info
        return sub
    }
}
