import AppKit
import QuartzCore
import simd

/// The text over the water: each fish's label, the presences', the footer, the banner and the little notes.
extension AppDelegate {
    // MARK: - labels (minimal / full / none)

    var labelMode: String { UserDefaults.standard.string(forKey: "labels") ?? "minimal" }

    @objc func cycleLabels() {
        let next = ["minimal": "full", "full": "none", "none": "minimal"][labelMode] ?? "minimal"
        UserDefaults.standard.set(next, forKey: "labels")
        tank.notice = (tr("rótulos: ") + tr(["minimal": "mínimo", "full": "completo", "none": "nenhum"][next]!), tank.time)
    }

    /// One short line (title or name) and, only when it matters, a second colored line:
    /// always if it needs you (request, question, error); for a few seconds when something happens.
    private func minimalLabel(_ f: Fish, _ l: CATextLayer) {
        if labelMode == "none" { l.opacity = 0; return }
        func short(_ t: String, _ n: Int) -> String { t.count > n ? String(t.prefix(n - 1)) + "…" : t }
        let near = hoverId == f.id
        let name = f.nickname.map { short($0, 22) } ?? (f.isAgent ? short(f.displayTitle ?? f.label, 22) : f.label)
        let s = NSMutableAttributedString(string: name, attributes: [
            .font: rounded(10.5, .medium), .foregroundColor: NSColor(white: 1, alpha: near ? 0.95 : 0.6)])
        let today = min(5, f.finished.filter { Calendar.current.isDateInToday($0.when) }.count)
        if today > 0 {
            s.append(NSAttributedString(string: " " + String(repeating: "●", count: today), attributes: [
                .font: rounded(6.5), .foregroundColor: NSColor(red: 0.95, green: 0.92, blue: 0.85, alpha: 0.7), .baselineOffset: 1.5]))
        }
        if let e = f.lastError, Date().timeIntervalSince(e) < 3600, f.state != .error {
            s.append(NSAttributedString(string: " ●", attributes: [
                .font: rounded(6.5), .foregroundColor: NSColor(red: 1, green: 0.4, blue: 0.35, alpha: 0.85), .baselineOffset: 1.5]))
        }
        let yellow = NSColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
        var line2: (String, NSColor)?
        if let p = permissions.request(ofFish: f.id) { line2 = (tr("✋ quer usar %@", p.tool), yellow) }
        else if f.state == .waiting { line2 = (f.asked.map { "✋ " + short($0, 38) } ?? tr("✋ esperando você"), yellow) }
        else if let o = f.offer { line2 = (o, yellow) }
        else if f.state == .error { line2 = (tr("✗ erro"), NSColor(red: 1, green: 0.45, blue: 0.4, alpha: 1)) }
        else if f.state == .alert { line2 = (tr("⚠︎ alerta"), NSColor(red: 1, green: 0.75, blue: 0.3, alpha: 1)) }
        else if f.compactingSince != nil { line2 = (tr("🫧 compactando…"), NSColor(white: 1, alpha: 0.6)) }
        else if let m = f.moment, tank.time < m.until {
            line2 = (m.text, NSColor(white: 1, alpha: CGFloat(min(1, m.until - tank.time)) * 0.6))
        }
        else if let m = f.mood { line2 = (m, NSColor(white: 1, alpha: 0.5)) }
        if let (t, color) = line2 {
            s.append(NSAttributedString(string: "\n" + t, attributes: [.font: rounded(10), .foregroundColor: color]))
        }
        l.string = s
        let sz = s.size()
        l.bounds = CGRect(x: 0, y: 0, width: ceil(sz.width) + 6, height: ceil(sz.height) + 2)
        l.position = CGPoint(x: CGFloat(f.pos.x), y: CGFloat(f.pos.y - f.size * 0.75) - l.bounds.height / 2)
        l.opacity = f.leaving ? 0.3 : 1
        l.zPosition = near ? 10 : 0
    }

    /// The text of each presence: its label always (except with labels off), and a second line with the detail while
    /// it needs you, for a few seconds after it changes, and on hover. See docs/scene.md.
    private func presenceLabels(_ scale: CGFloat) {
        var alive = Set<String>()
        func short(_ t: String, _ n: Int) -> String { t.count > n ? String(t.prefix(n - 1)) + "…" : t }
        for p in tank.scene.presences {
            alive.insert(p.id)
            let l = presenceLayers[p.id] ?? {
                let t = CATextLayer()
                t.contentsScale = scale
                t.alignmentMode = .center
                t.shadowOpacity = 0.75
                t.shadowRadius = 3
                t.shadowOffset = CGSize(width: 0, height: -0.5)
                t.shadowColor = NSColor(red: 0, green: 0.03, blue: 0.08, alpha: 1).cgColor
                labels.layer!.addSublayer(t)
                presenceLayers[p.id] = t
                return t
            }()
            let near = hoverPresence == p.id
            if labelMode == "none" && !near && !p.needsYou { l.opacity = 0; continue }
            if tank.compact && !p.needsYou { l.opacity = 0; continue }
            var name = short(p.label, 28)
            if p.kind.meter, p.detail == nil, let v = p.value { name += " · \(Int((v * 100).rounded()))%" }
            if near && p.link != nil { name += " ↗" }
            let s = NSMutableAttributedString(string: name, attributes: [
                .font: rounded(10.5, .medium), .foregroundColor: NSColor(white: 1, alpha: near ? 0.95 : 0.62)])
            let recent = tank.time - p.changedAt < 6
            var line2: (String, NSColor)?
            switch p.state {
            case .waiting: line2 = (p.detail.map { "✋ " + $0 } ?? p.state.label, NSColor(red: 1, green: 0.85, blue: 0.4, alpha: 1))
            case .alert: line2 = (p.detail.map { "⚠︎ " + $0 } ?? p.state.label, NSColor(red: 1, green: 0.75, blue: 0.3, alpha: 1))
            case .error: line2 = (p.detail.map { "✗ " + $0 } ?? p.state.label, NSColor(red: 1, green: 0.45, blue: 0.4, alpha: 1))
            default:
                let fade = near || labelMode == "full" ? 0.75 : CGFloat(max(0, min(1, 6 - (tank.time - p.changedAt)))) * 0.6
                if let d = p.detail, near || recent || labelMode == "full" { line2 = (d, NSColor(white: 1, alpha: fade)) }
                else if near, p.state != .ok { line2 = (p.state.label, NSColor(white: 1, alpha: 0.6)) }
            }
            if let (t, color) = line2 {
                s.append(NSAttributedString(string: "\n" + (near ? t : short(t, 44)), attributes: [.font: rounded(10), .foregroundColor: color]))
            }
            l.string = s
            let sz = s.size()
            l.bounds = CGRect(x: 0, y: 0, width: ceil(sz.width) + 6, height: ceil(sz.height) + 2)
            let (at, above) = tank.scene.labelAnchor(p)
            l.position = CGPoint(x: CGFloat(at.x), y: CGFloat(at.y) + (above ? 1 : -1) * l.bounds.height / 2)
            l.opacity = p.alpha
            l.zPosition = near ? 10 : 1
        }
        for (id, l) in presenceLayers where !alive.contains(id) {
            l.removeFromSuperlayer()
            presenceLayers[id] = nil
        }
    }

    func setupFooter() {
        let scale = window.backingScaleFactor
        calmText.alignmentMode = .center
        for l in [footer, banner, batteryText, pearlText, calmText] {
            l.contentsScale = scale
            l.fontSize = 11
            l.font = rounded(11, .medium)
            l.foregroundColor = NSColor(white: 1, alpha: 0.55).cgColor
            labels.layer!.addSublayer(l)
        }
        footer.alignmentMode = .left
        banner.alignmentMode = .center
        banner.fontSize = 15
        banner.font = rounded(15, .semibold)
        banner.foregroundColor = NSColor(white: 1, alpha: 0.9).cgColor
        banner.shadowOpacity = 0.8
        banner.shadowRadius = 3
        banner.shadowOffset = .zero
    }

    func updateLabels() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = window.backingScaleFactor
        var alive = Set<String>()
        for f in tank.fish where !f.decor {
            alive.insert(f.id)
            let l = textLayers[f.id] ?? {
                let t = CATextLayer()
                t.contentsScale = scale
                t.alignmentMode = .center
                t.shadowOpacity = 0.75
                t.shadowRadius = 3
                t.shadowOffset = CGSize(width: 0, height: -0.5)
                t.shadowColor = NSColor(red: 0, green: 0.03, blue: 0.08, alpha: 1).cgColor
                labels.layer!.addSublayer(t)
                textLayers[f.id] = t
                return t
            }()
            if tank.isHidden(f) { l.opacity = 0; continue }        // widget mode: only who needs you
            if labelMode != "full" {
                minimalLabel(f, l)
                continue
            }
            var state = f.stateLabel
            if f.state == .busy, let tool = f.tool { state += " · \(tool)" }
            if let c = f.context, c >= 0.05 { state += tr(" · %d%% contexto", Int((c * 100).rounded())) }
            if f.compactingSince != nil { state = tr("🫧 compactando…") }
            if let p = permissions.request(ofFish: f.id) { state = tr("✋ quer usar %@ · clique para responder", p.tool) }
            else if f.state == .waiting, let q = f.asked { state = tr("✋ te perguntou: ") + q }
            let s = NSMutableAttributedString(string: f.nickname ?? f.label, attributes: [
                .font: rounded(11, .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.92)])
            // plugin fish stay compact (name and state); details show on hover.
            // Claude sessions and anything needing attention show everything.
            let full = f.isAgent || hoverId == f.id
                || Attention.level(f.source, f.state) >= .attention
            // dots: one pearl per task finished today (up to 5) and a red dot if there was an error in the last hour
            let today = min(5, f.finished.filter { Calendar.current.isDateInToday($0.when) }.count)
            if today > 0 {
                s.append(NSAttributedString(string: " " + String(repeating: "●", count: today), attributes: [
                    .font: rounded(7), .foregroundColor: NSColor(red: 0.95, green: 0.92, blue: 0.85, alpha: 0.85), .baselineOffset: 1.5]))
            }
            if let e = f.lastError, Date().timeIntervalSince(e) < 3600, f.state != .error {
                s.append(NSAttributedString(string: " ●", attributes: [
                    .font: rounded(7), .foregroundColor: NSColor(red: 1, green: 0.4, blue: 0.35, alpha: 0.9), .baselineOffset: 1.5]))
            }
            var detail = full ? (f.sub ?? "") : ""
            if let b = f.branch, b != "main", b != "master", b != "HEAD" { detail = "⎇ \(b)" + (detail.isEmpty ? "" : "  ·  " + detail) }
            if !detail.isEmpty {
                s.append(NSAttributedString(string: "  " + detail, attributes: [
                    .font: rounded(10), .foregroundColor: NSColor(white: 1, alpha: 0.5)]))
            }
            if full, let t = f.displayTitle {
                s.append(NSAttributedString(string: "\n" + t, attributes: [
                    .font: rounded(10, .medium), .foregroundColor: NSColor(white: 1, alpha: 0.78)]))
            }
            let color: NSColor = f.state == .waiting ? NSColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
                : f.state == .error ? NSColor(red: 1, green: 0.45, blue: 0.4, alpha: 1)
                : NSColor(white: 1, alpha: 0.55)
            s.append(NSAttributedString(string: "\n" + state, attributes: [.font: rounded(10), .foregroundColor: color]))
            l.string = s
            let sz = s.size()
            l.bounds = CGRect(x: 0, y: 0, width: ceil(sz.width) + 6, height: ceil(sz.height) + 2)
            l.position = CGPoint(x: CGFloat(f.pos.x), y: CGFloat(f.pos.y - f.size * 0.75) - l.bounds.height / 2)
            l.opacity = f.leaving ? 0.3 : 1
            l.zPosition = hoverId == f.id ? 10 : 0
        }
        for (id, l) in textLayers where !alive.contains(id) {
            l.removeFromSuperlayer()
            textLayers[id] = nil
        }
        presenceLabels(scale)

        var parts = [tr("clique no peixe: ir até ele"), tr("no vazio: alimentar"), "D demo\(demo.on ? " ✓" : "")", tr("M som") + (synth.muted.load(ordering: .relaxed) ? " ✗" : ""),
                      tr("T flutuar") + (window.level == .floating ? " ✓" : ""), tr("S foco") + (Attention.focus ? " ✓" : ""), tr("L rótulos"), tr("E temas"), "127.0.0.1:\(port)"]
        for (k, v) in tank.gauges.values.sorted(by: { $0.key < $1.key }) where k != "mac:battery" && k != "mac:charging" {
            parts.append("\(k.split(separator: ":").last ?? "") \(Int(v * 100))%")
        }
        if let n = music.pieceName { parts.insert("🎵 " + n, at: 0) }
        var vis: [String] = []
        if visual.auroraBackground || visual.auroraChosen { vis.append("✨ aurora (\(visual.auroraDescription))") }
        if let m = visual.mode, !m.isAurora { vis.append(m.title) }
        if !vis.isEmpty { parts.insert(vis.joined(separator: " + "), at: min(1, parts.count)) }
        footer.string = parts.joined(separator: "   ·   ")
        footer.frame = CGRect(x: 14, y: 6, width: labels.bounds.width - 28, height: 16)
        // the footer shows while you use the window (mouse moving over it) and fades out a few seconds later
        let wanted: Float = tank.cursor != nil && tank.time - tank.cursorAt < 4 ? 1 : 0
        footerOpacity += (wanted - footerOpacity) * (wanted > footerOpacity ? 0.25 : 0.04)
        footer.opacity = tank.compact || demoQuiet ? 0 : footerOpacity
        // widget mode with nobody needing you: a quiet line in the middle
        let anyone = tank.fish.contains { !$0.decor && !$0.leaving && [.waiting, .error, .alert].contains($0.state) }
            || tank.scene.presences.contains { !$0.leaving && $0.needsYou }
        calmText.string = tr("✓ ninguém esperando")
        calmText.frame = CGRect(x: 0, y: labels.bounds.height / 2 - 9, width: labels.bounds.width, height: 18)
        calmText.opacity = tank.compact && !anyone ? 0.55 : 0

        if let b = tank.battery {
            batteryText.string = "\(Int((b * 100).rounded()))%" + (tank.pluggedIn ? " ⚡︎" : "")
            batteryText.fontSize = 10
            batteryText.alignmentMode = .center
            batteryText.foregroundColor = (b < 0.2 ? NSColor(red: 1, green: 0.5, blue: 0.45, alpha: 0.9) : NSColor(white: 1, alpha: 0.6)).cgColor
            let p = tank.batteryPos
            batteryText.frame = CGRect(x: CGFloat(p.x) - 30, y: CGFloat(p.y) + 12, width: 60, height: 14)
            // just a detail: the number shows on hover, or always if it's running out
            batteryText.opacity = hoverBattery || b < 0.2 ? 1 : 0
        } else {
            batteryText.opacity = 0
        }

        controlCard()

        if let p = hoverPearl {
            let hour = DateFormatter.localizedString(from: Date(timeIntervalSince1970: p.hour), dateStyle: .none, timeStyle: .short)
            pearlText.string = "\(p.project) · \(hour)\n\(p.title)"
            pearlText.fontSize = 10
            pearlText.alignmentMode = .center
            pearlText.foregroundColor = NSColor(white: 1, alpha: 0.85).cgColor
            let q = tank.pearls.pos(p)
            pearlText.frame = CGRect(x: CGFloat(q.x) - 140, y: CGFloat(q.y) + 10, width: 280, height: 28)
            pearlText.opacity = 1
        } else {
            pearlText.opacity = 0
        }

        if let (txt, t) = tank.notice, tank.time - t < 4 {
            banner.string = (tank.noticeIcon.map { $0 + " " } ?? "") + txt
            banner.opacity = Float(min(1, 4 - (tank.time - t)))
        } else {
            banner.opacity = 0
        }
        banner.frame = CGRect(x: 0, y: labels.bounds.height - 56, width: labels.bounds.width, height: 22)
        CATransaction.commit()
    }
}
