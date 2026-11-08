import AppKit
import CoreGraphics

/// What happened in the aquarium (for the "Enquanto você estava fora" summary).
struct Happening {
    enum Kind { case done, error, waiting, merge, event }
    let when: Date
    let kind: Kind
    let label: String
    let fishId: String?
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
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.gaze() }
    }

    func record(_ kind: Happening.Kind, _ label: String, fish: String? = nil) {
        items.append(Happening(when: Date(), kind: kind, label: label, fishId: fish))
        let day = Date().addingTimeInterval(-86400)
        if items.count > 2000 { items.removeAll { $0.when < day } }
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

    /// The summary as text, grouped.
    func text(_ list: [Happening]) -> [String] {
        func names(_ t: Happening.Kind) -> [String] {
            var seen = Set<String>(), out: [String] = []
            for a in list where a.kind == t && !seen.contains(a.label) { seen.insert(a.label); out.append(a.label) }
            return out
        }
        func joinList(_ l: [String]) -> String { l.count <= 3 ? l.joined(separator: ", ") : l.prefix(3).joined(separator: ", ") + tr(" e mais %d", l.count - 3) }
        var lines: [String] = []
        let t = list.filter { $0.kind == .done }.count
        if t > 0 { lines.append(tr(t == 1 ? "✓ %d tarefa terminou: %@" : "✓ %d tarefas terminaram: %@", t, joinList(names(.done)))) }
        let e = names(.error)
        if !e.isEmpty { lines.append(tr("✗ %d com erro: %@", e.count, joinList(e))) }
        let w = names(.waiting)
        if !w.isEmpty { lines.append(tr(w.count == 1 ? "✋ %d ficou esperando você: %@" : "✋ %d ficaram esperando você: %@", w.count, joinList(w))) }
        let m = names(.merge)
        if !m.isEmpty { lines.append(tr(m.count == 1 ? "🎉 %d PR mergeado: %@" : "🎉 %d PRs mergeados: %@", m.count, joinList(m))) }
        let ev = names(.event)
        if !ev.isEmpty { lines.append("🍤 \(joinList(ev))") }
        return lines.isEmpty ? [tr("Nada de novo. O aquário ficou tranquilo.")] : lines
    }
}

/// The summary card, on top of the aquarium.
final class SummaryView: NSView {
    var close: (() -> Void)?

    init(title: String, lines: [String]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.03, green: 0.07, blue: 0.12, alpha: 0.88).cgColor
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 15, weight: .semibold)
        t.textColor = NSColor(white: 1, alpha: 0.95)
        var views: [NSView] = [t]
        for l in lines {
            let f = NSTextField(wrappingLabelWithString: l)
            f.font = .systemFont(ofSize: 13)
            f.textColor = NSColor(white: 1, alpha: 0.82)
            f.preferredMaxLayoutWidth = 420
            views.append(f)
        }
        let ok = NSButton(title: tr("Ok"), target: self, action: #selector(closeClicked))
        ok.bezelStyle = .rounded
        ok.keyEquivalent = "\u{1b}"
        views.append(ok)
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 460),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func closeClicked() { close?() }
}
