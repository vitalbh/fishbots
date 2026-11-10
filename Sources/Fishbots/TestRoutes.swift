import AppKit
import simd

/// Routes for driving the app without a mouse: tests, screenshots and the demo recordings (scripts/demo).
extension AppDelegate {
    /// nil: not one of them.
    func testRoute(_ route: String, _ path: String) -> (Int, Data)? {
        switch route {
        case "/test/whale":
            self.tank.fauna.callWhale(self.tank)
            return (200, Data(#"{"ok":true}"#.utf8))
        case "/test/card":
            // to test the hover card without moving the mouse
            let goal = path.components(separatedBy: "f=").dropFirst().first?.removingPercentEncoding
            if let f = self.tank.fish.first(where: { ($0.isAgent || goal != nil) && !$0.leaving && (goal == nil || $0.id.hasSuffix(goal!)) }) {
                self.hoverId = f.id                      // pretend the mouse is over it, so the card doesn't close
                self.hoverSince = Date(timeIntervalSinceNow: -1)
                self.showCard(f)
            }
            return (200, Data(#"{"ok":true}"#.utf8))
        case "/test/preferences":
            // to check the preferences window without clicking: ?tab=0…3
            let tab = path.components(separatedBy: "tab=").dropFirst().first.flatMap { Int($0.prefix(1)) }
            self.preferences.show(tab: tab)
            return (200, Data(#"{"ok":true}"#.utf8))
        case "/test/music-paused":
            // as if your music had played and paused: the music fish offers the aquarium's
            self.music.yielded = true
            self.music.onUserMusicPaused?()
            return (200, Data(#"{"ok":true}"#.utf8))
        case "/test/themes":
            self.openThemePicker()
            return (200, Data(#"{"ok":true}"#.utf8))
        case "/test/swatches":
            // the Tema menu's pictures, side by side, written to ?out=<file.png>
            let out = path.components(separatedBy: "out=").dropFirst().first?.removingPercentEncoding ?? "/tmp/swatches.png"
            let shots = self.themeSwatches
            let w = 120 * shots.count
            if w > 0, let ctx = CGContext(data: nil, width: w, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
                for (i, t) in Themes.all.enumerated() { if let img = shots[t.id] { ctx.draw(img, in: CGRect(x: i * 120, y: 0, width: 120, height: 80)) } }
                if let img = ctx.makeImage(), let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil) {
                    CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst)
                }
            }
            return (200, Data("{\"themes\":\(shots.count)}".utf8))
        case "/test/catalog":
            // ?install=<id>: installs that pack from the catalog, as the button would
            if let id = path.components(separatedBy: "install=").dropFirst().first {
                PackCatalog.fetch { r in
                    guard case .success(let all) = r, let e = all.first(where: { $0.id == id }) else { return }
                    PackCatalog.install(e) { res in
                        if case .success = res { self.reloadPacks() }
                        FileHandle.standardError.write(Data("catalog install \(id): \(res)\n".utf8))
                    }
                }
            } else { self.explorePacks() }
            return (200, Data(#"{"ok":true}"#.utf8))
        case "/test/do":
            // acting out a demo (scripts/demo): ?audio=start:<file>|stop &window=w,h &key=⇥|a|w|… &theme=<id> &hour=<h>|off &visual=<id>
            // &feed=x,y &knock=x,y &drag=x1,y1,x2,y2 (x, y: 0…1 of the water, y from the bottom)
            var q: [String: String] = [:]
            for kv in (path.split(separator: "?").dropFirst().first ?? "").split(separator: "&") {
                let p = kv.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
                if p.count == 2 { q[p[0]] = p[1] }
            }
            let at: (String) -> [SIMD2<Float>] = { s in
                let n = s.split(separator: ",").compactMap { Float($0) }
                return stride(from: 0, to: n.count - 1, by: 2).map { [n[$0] * self.tank.size.x, n[$0 + 1] * self.tank.size.y] }
            }
            if let w = q["window"]?.split(separator: ",").compactMap({ Double($0) }), w.count == 2 {
                self.window.setContentSize(NSSize(width: w[0], height: w[1])); self.window.center()
                // a Retina screen, if there is one: sharper, and the fish come out bigger for the same pixels
                if let sc = NSScreen.screens.first(where: { $0.backingScaleFactor >= 2 }) {
                    let f = self.window.frame, v = sc.visibleFrame
                    self.window.setFrameOrigin(NSPoint(x: v.midX - f.width / 2, y: v.midY - f.height / 2))
                }
            }
            if q["footer"] == "off" { self.demoQuiet = true }
            if let a = q["audio"] {
                // "start:<file.caf>" writes the app's sound (the voice mixed in) from now on; "stop" ends it
                if a.hasPrefix("start:") { DemoAudio.start(self.synth.engine, to: URL(fileURLWithPath: String(a.dropFirst(6)))) }
                else { DemoAudio.stop(self.synth.engine) }
            }
            if let t = q["theme"] { self.useTheme(t) }
            if let h = q["hour"] { self.demoHour = Float(h) }
            if let v = q["visual"] { self.visual.choice = v }
            if let k = q["key"] { self.key(k) }
            if let p = q["feed"].map(at)?.first { self.tank.feed(at: p) }
            if let p = q["knock"].map(at)?.first {
                self.tank.knock(at: p)
                self.music.sceneSound("glass", cue: .effect, x: p.x / max(1, self.tank.size.x))
            }
            if let d = q["drag"].map(at), d.count == 2 {
                // a sweep over ~0.6 s, in small steps, as the mouse would
                let steps = 24
                for i in 0..<steps {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.025) {
                        let a = d[0] + (d[1] - d[0]) * Float(i) / Float(steps), b = d[0] + (d[1] - d[0]) * Float(i + 1) / Float(steps)
                        self.tank.drag(from: a, to: b)
                        if i == steps - 1 { self.tank.endDrag() }
                    }
                }
            }
            return (200, Data(#"{"ok":true}"#.utf8))
        case "/test/widget":
            self.toggleWidget()
            return (200, Data(#"{"ok":true}"#.utf8))
        default:
            return nil
        }
    }
}
