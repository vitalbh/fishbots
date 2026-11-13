import AppKit
import CoreGraphics

/// What happened in the aquarium (for the "Enquanto você estava fora" summary).
struct Happening: Codable {
    enum Kind: String, Codable { case done, error, waiting, merge, event }
    let when: Date
    let kind: Kind
    /// The project (the fish's label), or the event's text.
    let label: String
    let fishId: String?
    // What the summary tells about it (all optional: the journal of an older version has none of them).
    /// The session's name (its nickname) and its conversation's title.
    var name: String?
    var title: String?
    /// What it was asked to do (the prompt that started this piece of work).
    var task: String?
    /// Its own words: the start of its last reply (done), what it asks (waiting), where it broke (error).
    var said: String?
    /// How long the piece of work took and how many steps it made.
    var took: Double?
    var steps: Int?
    var branch: String?
    /// Its color (the fish may be gone when the summary is read).
    var color: [Float]?
    /// A plugin's presence ("source:id") this is about, instead of a fish.
    var presence: String?
    var link: String?

    init(when: Date, kind: Kind, label: String, fishId: String?) {
        self.when = when; self.kind = kind; self.label = label; self.fishId = fishId
    }
}

final class Journal {
    private(set) var items: [Happening] = []
    /// When you left (no Mac activity for 10 min); nil if you're here.
    private(set) var awaySince: Date?
    /// Summary ready to show when you come back.
    private(set) var pending: (since: Date, until: Date)?
    var returned: (() -> Void)?
    private var timer: Timer?
    private let limit: TimeInterval = 600 * Tank.scale

    init() {
        // the last day's happenings come back when the app reopens ("what happened today?" still has an answer)
        let day = Date().addingTimeInterval(-86400)
        if let d = try? Data(contentsOf: Self.url), let saved = try? JSONDecoder().decode([Happening].self, from: d) {
            items = saved.filter { $0.when > day }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.gaze() }
    }

    /// Where the day's happenings are kept between runs.
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fishbots/journal.json")
    }
    private var saveAt: DispatchWorkItem?

    /// Writes the last day to disk, a few seconds after the last thing that happened (or right now, on quitting).
    func save(now: Bool = false) {
        saveAt?.cancel()
        let write = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let day = Date().addingTimeInterval(-86400)
            guard let d = try? JSONEncoder().encode(self.items.filter { $0.when > day }) else { return }
            try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? d.write(to: Self.url, options: .atomic)
        }
        saveAt = write
        if now { write.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: write) }
    }

    func record(_ kind: Happening.Kind, _ label: String, fish: String? = nil) {
        add(Happening(when: Date(), kind: kind, label: label, fishId: fish))
    }

    func add(_ h: Happening) {
        items.append(h)
        let day = Date().addingTimeInterval(-86400)
        if items.count > 2000 { items.removeAll { $0.when < day } }
        save()
    }

    /// Changes the last happening of a fish (its reply arrives a moment after it finishes).
    func amendLast(of fish: String, _ kind: Happening.Kind, _ change: (inout Happening) -> Void) {
        guard let i = items.lastIndex(where: { $0.fishId == fish && $0.kind == kind }) else { return }
        change(&items[i])
        save()
    }

    /// Your last time away: from when the Mac went quiet until you came back (kept between runs).
    var lastAway: (since: Date, until: Date)? {
        // numbers, or text when it comes from the command line (-lastAway "(since, until)")
        let a = (UserDefaults.standard.array(forKey: "lastAway") ?? []).compactMap { ($0 as? NSNumber)?.doubleValue ?? ($0 as? String).flatMap(Double.init) }
        guard a.count == 2 else { return nil }
        return (Date(timeIntervalSince1970: a[0]), Date(timeIntervalSince1970: a[1]))
    }
    private func keepAway(_ since: Date, _ until: Date) {
        UserDefaults.standard.set([since.timeIntervalSince1970, until.timeIntervalSince1970], forKey: "lastAway")
    }

    /// What happened since `since`, for GET /journal and the assistant: when, what, and whose.
    func json(since: Date) -> Data {
        let f = ISO8601DateFormatter()
        let list: [[String: Any]] = items.filter { $0.when >= since }.map { h -> [String: Any] in
            var d: [String: Any] = ["when": f.string(from: h.when), "kind": h.kind.rawValue, "label": h.label, "fish": h.fishId ?? ""]
            for (k, v) in [("title", h.title), ("task", h.task), ("said", h.said), ("presence", h.presence), ("branch", h.branch)] { if let v { d[k] = v } }
            if let t = h.took { d["took"] = Int(t) }
            if let n = h.steps { d["steps"] = n }
            return d
        }
        return (try? JSONSerialization.data(withJSONObject: ["journal": list], options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    func between(_ a: Date, _ b: Date) -> [Happening] { items.filter { $0.when >= a && $0.when <= b } }

    func discardPending() { pending = nil }

    /// Tempo sem teclado nem mouse.
    private var idle: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private func gaze() {
        let o = idle
        if awaySince == nil, o > limit {
            awaySince = Date().addingTimeInterval(-o)
        } else if let since = awaySince, o < 5 {
            awaySince = nil
            keepAway(since, Date())
            // only worth showing if something happened
            if !between(since, Date()).isEmpty {
                pending = (since, Date())
                returned?()
            }
        }
    }

    static func duration(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        if m < 60 { return "\(max(1, m)) min" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h\(String(format: "%02d", m % 60))"
    }
}
