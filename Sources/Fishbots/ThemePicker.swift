import AppKit

/// A window that Esc closes (the themes window, Preferences), unless something inside takes Esc first (recording a
/// shortcut cancels the recording instead).
final class EscClosingWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }
}

/// The "Escolher tema…" window (E): the installed themes with a big picture, where each comes from, what it brings
/// and a button to use it; a surprise mode that picks another theme by itself every hour or every day; and a way to
/// the catalog for more.
final class ThemePickerWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let list = NSStackView()
    private var pictures: [String: NSButton] = [:]
    private var titles: [String: NSTextField] = [:]
    private weak var scroll: NSScrollView?
    /// Apply a theme (the app's chooseTheme), open the catalog.
    var onChoose: ((String) -> Void)?
    var onExplore: (() -> Void)?

    func show() {
        if let w = window { refresh(); w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = EscClosingWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 660), styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        w.title = tr("Temas")
        w.isReleasedWhenClosed = false
        w.delegate = self
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 16
        list.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        // it fills what the window has, instead of asking for the whole list's height (which pushed the top out of view)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.drawsBackground = false
        let doc = Flipped()
        doc.translatesAutoresizingMaskIntoConstraints = false
        list.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(list)
        scroll.documentView = doc
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: doc.topAnchor), list.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: doc.trailingAnchor), list.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            // pinned to the clip view's top: the list starts at the top (scrolling moves the clip view's bounds)
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
        ])
        // the footer: the surprise mode and the catalog
        let surprise = NSPopUpButton(frame: .zero, pullsDown: false)
        for (title, value) in [(tr("desligado"), "off"), (tr("a cada hora"), "hour"), (tr("a cada dia"), "day")] {
            surprise.addItem(withTitle: title)
            surprise.lastItem?.representedObject = value
        }
        let current = UserDefaults.standard.string(forKey: "surpriseTheme") ?? "off"
        surprise.selectItem(at: ["off", "hour", "day"].firstIndex(of: current) ?? 0)
        surprise.target = self
        surprise.action = #selector(setSurprise(_:))
        let surpriseLabel = NSTextField(labelWithString: tr("Tema surpresa:"))
        let explore = NSButton(title: tr("Explorar pacotes…"), target: self, action: #selector(explore(_:)))
        explore.bezelStyle = .rounded
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [surpriseLabel, surprise, spacer, explore])
        footer.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 12, right: 16)
        let root = NSStackView(views: [scroll, footer])
        root.orientation = .vertical
        root.spacing = 0
        w.contentView = root
        w.center()
        window = w
        self.scroll = scroll
        refresh()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        scrollToTop()
    }

    private final class Flipped: NSView { override var isFlipped: Bool { true } }


    /// From the top (once the window has laid itself out).
    private func scrollToTop() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let s = self?.scroll, let doc = s.documentView else { return }
            s.layoutSubtreeIfNeeded()
            // the clip view takes the document's flippedness: y = 0 is the top when it's flipped
            let y = s.contentView.isFlipped ? 0 : max(0, doc.frame.height - s.contentView.bounds.height)
            s.contentView.scroll(to: NSPoint(x: 0, y: y))
            s.reflectScrolledClipView(s.contentView)
        }
    }

    func refresh() {
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        titles = [:]; pictures = [:]
        let builtIn = Themes.all.filter { Packs.themePack[$0.id] == nil }, fromPacks = Themes.all.filter { Packs.themePack[$0.id] != nil }
        for t in builtIn + fromPacks { row(t) }
        scrollToTop()
        // the pictures, a little bigger than the menu's, drawn in the background
        let job = PackPreview.swatchJob(Themes.all, cellW: 240)
        DispatchQueue.global(qos: .userInitiated).async {
            let images = PackPreview.themeSwatches(job)
            DispatchQueue.main.async { [weak self] in
                for (id, img) in images { self?.pictures[id]?.image = NSImage(cgImage: img, size: NSSize(width: 192, height: 128)) }
            }
        }
    }

    private func row(_ t: Theme) {
        // the picture is the button: a click uses the theme
        let pic = NSButton(title: "", target: self, action: #selector(use(_:)))
        pic.isBordered = false
        pic.refusesFirstResponder = true                     // (focusing one would scroll the window to it)
        pic.imagePosition = .imageOnly
        pic.imageScaling = .scaleProportionallyUpOrDown
        pic.identifier = NSUserInterfaceItemIdentifier(t.id)
        pic.toolTip = t.displayName
        pic.wantsLayer = true
        pic.layer?.cornerRadius = 8
        pic.layer?.masksToBounds = true
        pic.layer?.backgroundColor = NSColor(white: 0.15, alpha: 1).cgColor
        pic.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([pic.widthAnchor.constraint(equalToConstant: 192), pic.heightAnchor.constraint(equalToConstant: 128)])
        pictures[t.id] = pic
        let title = NSTextField(labelWithString: t.displayName)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        titles[t.id] = title
        let origin: String
        if let pid = Packs.themePack[t.id], let p = Packs.loaded.first(where: { $0.id == pid }) {
            origin = tr("do pacote %@", p.name) + (p.meta["author"].map { " · " + tr("por %@", $0) } ?? "")
        } else { origin = tr("nativo") }
        let from = NSTextField(labelWithString: origin)
        from.font = .systemFont(ofSize: 11)
        from.textColor = .secondaryLabelColor
        let desc = NSTextField(wrappingLabelWithString: t.displayDescription)
        desc.font = .systemFont(ofSize: 12)
        desc.preferredMaxLayoutWidth = 360
        let what = NSTextField(wrappingLabelWithString: brings(t).joined(separator: " · "))
        what.font = .systemFont(ofSize: 11)
        what.textColor = .tertiaryLabelColor
        what.preferredMaxLayoutWidth = 360
        let text = NSStackView(views: [title, from, desc, what])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        let row = NSStackView(views: [pic, text])
        row.alignment = .top
        row.spacing = 16
        list.addArrangedSubview(row)
        mark(t.id)
    }

    /// What a theme brings, in a few words.
    private func brings(_ t: Theme) -> [String] {
        var out: [String] = []
        if t.uniforms.pack.x > 0.5 { out.append(tr("fundo próprio")) }
        if t.sky != nil { out.append(tr("céu próprio")) }
        if !t.looks.isEmpty { out.append(tr("%@ peças com outro visual", "\(t.looks.count)")) }
        let fauna = (t.fauna ?? []).map { id in FaunaKinds.all.first { $0.id == id }?.name ?? tr(Self.faunaNames[id] ?? id) }
        if !fauna.isEmpty { out.append(tr("criaturas: %@", fauna.joined(separator: ", "))) }
        if let m = t.music, let s = Generator.styles.first(where: { $0.id == m }) { out.append(tr("música: %@", tr(s.name))) }
        return out
    }
    private static let faunaNames = ["crab": "caranguejo", "starfish": "estrela-do-mar", "turtle": "tartaruga", "snail": "caramujo",
                                     "lanternfish": "peixe-lanterna", "whale": "baleia", "grouper": "garoupa",
                                     "anglerfish": "peixe-abissal", "sunfish": "peixe-lua",
                                     "manatee": "peixe-boi", "seahorses": "cavalos-marinhos"]

    /// The theme in use: a border in the accent color around its picture, and "✓ em uso" by its name.
    private func mark(_ id: String) {
        let t = Themes.all.first { $0.id == id }
        let current = Themes.current.id == id
        pictures[id]?.layer?.borderWidth = current ? 3 : 0
        pictures[id]?.layer?.borderColor = NSColor.controlAccentColor.cgColor
        let s = NSMutableAttributedString(string: t?.displayName ?? id, attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold)])
        if current {
            s.append(NSAttributedString(string: "   ✓ " + tr("em uso"), attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium),
                                                                               .foregroundColor: NSColor.controlAccentColor]))
        }
        titles[id]?.attributedStringValue = s
    }

    @objc private func use(_ b: NSButton) {
        guard let id = b.identifier?.rawValue else { return }
        onChoose?(id)
        for tid in pictures.keys { mark(tid) }
    }

    @objc private func setSurprise(_ p: NSPopUpButton) {
        UserDefaults.standard.set(p.selectedItem?.representedObject as? String ?? "off", forKey: "surpriseTheme")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "surpriseThemeAt")
    }

    @objc private func explore(_ b: NSButton) { onExplore?() }
}
