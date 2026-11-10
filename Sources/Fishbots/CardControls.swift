import AppKit
import QuartzCore

/// The song's progress: elapsed time, a thin bar, the length ("1:12 ━━━━──── 5:15"); the bar dims while paused.
final class SongBar: NSStackView {
    private let progress: () -> (pos: Double, dur: Double, playing: Bool)?
    private let elapsed = NSTextField(labelWithString: "")
    private let total = NSTextField(labelWithString: "")
    private let track = NSView(), fill = NSView(), knob = NSView()
    private var fillWidth: NSLayoutConstraint!
    /// The bar's color (the music card: the album's, bright, glowing), nil: the usual teal.
    var tint: NSColor? { didSet { styleTint() } }

    init(progress: @escaping () -> (pos: Double, dur: Double, playing: Bool)?) {
        self.progress = progress
        super.init(frame: .zero)
        spacing = 8
        for l in [elapsed, total] {
            l.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
            l.textColor = .secondaryLabelColor
        }
        track.wantsLayer = true
        track.layer?.cornerRadius = 2
        track.layer?.backgroundColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.25).cgColor
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 2
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)
        knob.wantsLayer = true
        knob.layer?.cornerRadius = 5
        knob.translatesAutoresizingMaskIntoConstraints = false
        knob.isHidden = true
        track.addSubview(knob)
        fillWidth = fill.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            track.heightAnchor.constraint(equalToConstant: 4),
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fillWidth,
            knob.widthAnchor.constraint(equalToConstant: 10), knob.heightAnchor.constraint(equalToConstant: 10),
            knob.centerYAnchor.constraint(equalTo: track.centerYAnchor), knob.centerXAnchor.constraint(equalTo: fill.trailingAnchor),
        ])
        addArrangedSubview(elapsed)
        addArrangedSubview(track)
        addArrangedSubview(total)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func time(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }

    override func layout() { super.layout(); refresh() }

    /// Click or drag along the bar to jump there in the song (nil: it only shows the progress).
    var onSeek: ((Double) -> Void)?
    private var dragging: Double?
    override func resetCursorRects() { if onSeek != nil { addCursorRect(convert(track.bounds, from: track), cursor: .pointingHand) } }
    private func fraction(_ e: NSEvent) -> Double? {
        let p = track.convert(e.locationInWindow, from: nil)
        guard track.bounds.width > 0, p.x > -8, p.x < track.bounds.width + 8 else { return nil }
        return Double(max(0, min(1, p.x / track.bounds.width)))
    }
    override func mouseDown(with e: NSEvent) {
        guard onSeek != nil, let f = fraction(e), let p = progress() else { return super.mouseDown(with: e) }
        dragging = f * p.dur
        refresh()
    }
    override func mouseDragged(with e: NSEvent) {
        guard dragging != nil, let f = fraction(e), let p = progress() else { return }
        dragging = f * p.dur
        refresh()
    }
    override func mouseUp(with e: NSEvent) {
        guard let s = dragging else { return }
        dragging = nil
        onSeek?(s)
    }

    func refresh() {
        guard let p = progress() else { return }
        let pos = dragging ?? p.pos                       // while dragging, where it would go
        elapsed.stringValue = Self.time(pos)
        total.stringValue = Self.time(p.dur)
        fillWidth.constant = track.bounds.width * CGFloat(pos / max(1, p.dur))
        fill.layer?.backgroundColor = (p.playing ? (tint ?? .systemTeal) : NSColor.secondaryLabelColor).cgColor
        fill.layer?.shadowOpacity = tint != nil && p.playing ? 0.95 : 0
        knob.layer?.shadowOpacity = p.playing ? 1 : 0.3
    }

    /// The album's color on the bar: a glow around the filled part and a lit knob at its end.
    private func styleTint() {
        guard let c = tint else { knob.isHidden = true; return }
        track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        track.layer?.masksToBounds = false
        for l in [fill.layer, knob.layer] {
            l?.shadowColor = c.cgColor
            l?.shadowRadius = 5
            l?.shadowOffset = .zero
            l?.masksToBounds = false
        }
        knob.layer?.backgroundColor = NSColor.white.cgColor
        knob.isHidden = false
        for l in [elapsed, total] { l.textColor = NSColor.white.withAlphaComponent(0.65) }
        refresh()
    }
}

/// A borderless button that runs a closure (for the card's links).
final class ClosureButton: NSButton {
    private let run: () -> Void
    init(_ run: @escaping () -> Void) {
        self.run = run
        super.init(frame: .zero)
        target = self
        action = #selector(fire)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func fire() { run() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
