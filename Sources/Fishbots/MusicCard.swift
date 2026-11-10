import AppKit
import CoreImage
import QuartzCore
import simd

/// The music fish's card: now playing, with the album art, the player's buttons and the song's bar.
extension FishCard {
    // MARK: - the music fish's card

    /// "Now playing": the album art blurred behind everything, the cover big with the song and the artist beside it,
    /// the player's buttons, the song's progress.
    func musicCard() -> NSView {
        let w: CGFloat = 360, cover: CGFloat = 112
        var title = f.label
        if title.hasPrefix("♪ ") { title.removeFirst(2) }
        let artist = f.sub ?? ""
        if !artist.isEmpty, title.hasSuffix(" — " + artist) { title = String(title.dropLast(artist.count + 3)) }
        let player = (f.link ?? "").hasPrefix("spotify") ? "Spotify" : "Music"
        let accent = NSColor(red: CGFloat(f.color.x), green: CGFloat(f.color.y), blue: CGFloat(f.color.z), alpha: 1)

        // the cover (or a note on the fish's color while it loads)
        let art = NSImageView()
        art.wantsLayer = true
        art.layer?.cornerRadius = 10
        art.layer?.masksToBounds = true
        art.imageScaling = .scaleProportionallyUpOrDown
        if let a = f.art { art.image = NSImage(cgImage: a, size: NSSize(width: cover, height: cover)) }
        else {
            art.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 40, weight: .light))
            art.contentTintColor = .white.withAlphaComponent(0.8)
            art.layer?.backgroundColor = accent.withAlphaComponent(0.35).cgColor
            art.imageScaling = .scaleNone
        }
        art.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([art.widthAnchor.constraint(equalToConstant: cover), art.heightAnchor.constraint(equalToConstant: cover)])
        let artBox = NSView()
        artBox.wantsLayer = true
        artBox.shadow = { let s = NSShadow(); s.shadowBlurRadius = 14; s.shadowOffset = NSSize(width: 0, height: -4)
                          s.shadowColor = NSColor.black.withAlphaComponent(0.6); return s }()
        artBox.addSubview(art)
        artBox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            artBox.widthAnchor.constraint(equalToConstant: cover), artBox.heightAnchor.constraint(equalToConstant: cover),
            art.leadingAnchor.constraint(equalTo: artBox.leadingAnchor), art.topAnchor.constraint(equalTo: artBox.topAnchor),
        ])

        let playing = NowPlaying.playing
        let status = text((playing ? tr("♪ tocando agora") : (f.mood ?? tr("⏸ pausado"))).uppercased(), 9.5, .bold,
                          color: playing ? .white.withAlphaComponent(0.75) : .white.withAlphaComponent(0.5))
        let colW = w - cover - 16
        let name = text(title, 17, .bold, color: .white)
        name.font = rounded(17, .bold)
        name.maximumNumberOfLines = 2
        name.preferredMaxLayoutWidth = colW
        let who = text(artist, 13, .medium, color: .white.withAlphaComponent(0.7))
        who.preferredMaxLayoutWidth = colW
        who.maximumNumberOfLines = 1

        // the player's buttons
        func control(_ symbol: String, _ size: CGFloat, _ command: String) -> NSButton {
            let b = ClosureButton { NowPlaying.control(player, command) }
            b.isBordered = false
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size, weight: .semibold))
            b.contentTintColor = .white
            b.toolTip = command
            return b
        }
        let controls = NSStackView(views: [control("backward.fill", 15, "previous track"),
                                           control(playing ? "pause.circle.fill" : "play.circle.fill", 30, "playpause"),
                                           control("forward.fill", 15, "next track")])
        controls.spacing = 18
        controls.alignment = .centerY

        let col = NSStackView(views: [status, name, who, NSView(), controls])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 4
        col.setCustomSpacing(10, after: who)
        col.heightAnchor.constraint(equalToConstant: cover).isActive = true
        let top = NSStackView(views: [artBox, col])
        top.alignment = .top
        top.spacing = 16

        var v: [NSView] = [top]
        if let p = f.progress, p() != nil {
            let bar = SongBar(progress: p)
            bar.onSeek = { s in NowPlaying.seek(player, to: s) }
            // the bar in the album's color: made bright enough to stand out on the dark card
            if let c = AlbumArt.colors?.0 {
                let m = max(c.x, max(c.y, c.z), 0.001)
                let b = simd_mix(c / m, SIMD3<Float>(repeating: 1), SIMD3(repeating: 0.15))
                bar.tint = NSColor(red: CGFloat(b.x), green: CGFloat(b.y), blue: CGFloat(b.z), alpha: 1)
            } else {
                bar.tint = accent.blended(withFraction: 0.3, of: .white)
            }
            bar.widthAnchor.constraint(equalToConstant: w).isActive = true
            songBar = bar
            v.append(bar)
        }
        let open = link(player == "Spotify" ? tr("abrir no Spotify ↗") : tr("abrir no Música ↗"), 10.5, color: .white.withAlphaComponent(0.55)) { [weak self] in self?.go?() }
        v.append(row([NSView(), open]))
        if let r = v.last as? NSStackView { r.widthAnchor.constraint(equalToConstant: w).isActive = true }

        let stack = NSStackView(views: v)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 12, right: 18)
        stack.widthAnchor.constraint(equalToConstant: w + 36).isActive = true

        // behind it all: the cover, blurred and darkened (or the fish's color)
        let bg = NSView()
        bg.appearance = NSAppearance(named: .darkAqua)
        bg.wantsLayer = true
        bg.layer?.backgroundColor = backdrop.cgColor
        let blur = CALayer()
        if let a = f.art {
            let ci = CIImage(cgImage: a)
            let soft = ci.clampedToExtent().applyingGaussianBlur(sigma: 22).cropped(to: ci.extent)
            blur.contents = CIContext().createCGImage(soft, from: ci.extent)
            blur.contentsGravity = .resizeAspectFill
        }
        let dim = CAGradientLayer()
        dim.colors = [NSColor.black.withAlphaComponent(0.35).cgColor, NSColor.black.withAlphaComponent(0.68).cgColor]
        dim.startPoint = CGPoint(x: 0.5, y: 1); dim.endPoint = CGPoint(x: 0.5, y: 0)
        bg.layer?.addSublayer(blur)
        bg.layer?.addSublayer(dim)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor), stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bg.topAnchor), stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
        ])
        bg.layoutSubtreeIfNeeded()
        bg.frame = NSRect(origin: .zero, size: bg.fittingSize)
        blur.frame = bg.bounds.insetBy(dx: -20, dy: -20)
        dim.frame = bg.bounds
        return bg
    }
}
