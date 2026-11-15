import CloudKit
import Foundation
import os
import Security

/// The iPhone's notifications through the person's own iCloud (Push.swift decides what's worth one): a note written
/// to the private database of the container the Mac and iPhone apps share, in the zone of the device it's for
/// (`device-<id>`), and the phone's subscription (iOS/Cloud.swift) makes Apple notify it, in well under a second. No
/// push key and no server of anyone's: it needs the Mac and the phone on the same Apple ID.
///
/// The note is the same sealed text as a direct push (PushSeal, the device's key): what's in iCloud can't be read
/// without the pairing. Notes are taken back after a few minutes; they only exist to ring the phone.
///
/// Only when the app is signed with the container (scripts/app.sh with a team): CloudKit stops an app that asks for a
/// container it isn't entitled to, so without it this stays off.
final class CloudNotes {
    static let containerId = "iCloud.io.vitalbh.fishbots"
    static let recordType = "Note"
    private static let log = Logger(subsystem: "io.vitalbh.fishbots", category: "cloud")

    /// The phones subscribed (they said so: `POST /push/register {"cloud": true}`), by paired device id.
    private(set) var devices: Set<String> = []
    private lazy var db = CKContainer(identifier: Self.containerId).privateCloudDatabase

    init() {
        devices = Set((try? JSONDecoder().decode([String].self, from: Data(contentsOf: Self.file))) ?? [])
    }

    /// Signed with the container: iCloud can be used.
    static let available: Bool = {
        guard let task = SecTaskCreateFromSelf(nil),
              let v = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String]
        else { return false }
        return v.contains(containerId)
    }()

    func register(_ device: String) {
        guard !devices.contains(device) else { return }
        devices.insert(device)
        save()
    }

    func forget(_ device: String) {
        guard devices.remove(device) != nil else { return }
        save()
    }

    /// Writes the sealed note in that device's zone (made first if the phone hasn't yet).
    func send(sealed: String, to device: String) {
        guard Self.available else { Self.log.info("no iCloud in this build"); return }
        let zone = CKRecordZone.ID(zoneName: "device-" + device, ownerName: CKCurrentUserDefaultName)
        let note = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(zoneID: zone))
        note["fb"] = sealed
        note["sent"] = Date().timeIntervalSince1970
        save(note, zone: zone, retry: true)
    }

    private func save(_ note: CKRecord, zone: CKRecordZone.ID, retry: Bool) {
        db.save(note) { [weak self] _, error in
            guard let self else { return }
            if let e = error as? CKError {
                if e.code == .zoneNotFound, retry {
                    self.db.save(CKRecordZone(zoneID: zone)) { _, _ in self.save(note, zone: zone, retry: false) }
                } else {
                    Self.log.error("note not written: \(e.localizedDescription, privacy: .public)")
                }
                return
            }
            if let error { Self.log.error("note not written: \(error.localizedDescription, privacy: .public)"); return }
            Self.log.info("note written for a device")
            // it has rung the phone: taken back in a while
            DispatchQueue.global().asyncAfter(deadline: .now() + 10 * 60) { [weak self] in
                self?.db.delete(withRecordID: note.recordID) { _, _ in }
            }
        }
    }

    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fishbots/push-cloud.json")
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(devices.sorted()) { try? ControlTokens.writePrivately(d, to: Self.file) }
    }
}
