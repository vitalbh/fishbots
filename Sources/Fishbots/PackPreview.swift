import AppKit
import Metal

/// `Fishbots --preview <pack folder> [--out sheet.png]` and `Fishbots --check <pack folder>`: without opening the
/// aquarium, reads one pack, compiles each of its drawings against the app's shader (reporting errors at the pack's
/// own file and line), and draws a sheet with all of them (fish in four patterns and asleep, scenery by day and by
/// night, creatures moving and resting), big and at their real size. For people (and agents) making packs.
enum PackPreview {
    /// Runs if the arguments ask for it; returns the exit code (nil: not a preview, open the app).
    static func runIfAsked() -> Int32? {
        let args = CommandLine.arguments
        if args.contains("--check-shaders") { return ShaderCheck.run(offline: args.contains("--offline")) }
        guard let i = args.firstIndex(where: { $0 == "--preview" || $0 == "--check" || $0 == "--cover" }), i + 1 < args.count else { return nil }
        let dir = URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath).standardizedFileURL
        let out = args.firstIndex(of: "--out").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
            ?? dir.appendingPathComponent(args[i] == "--cover" ? "cover.png" : "preview.png").path
        offline = args.contains("--offline")
        catalog = args.contains("--catalog")
        return run(dir, out: args[i] == "--check" ? nil : out, cover: args[i] == "--cover")
    }

    /// Compile with the offline compiler (`xcrun metal`) instead of the GPU: for machines without one (CI).
    private static var offline = false
    /// Also require what the community catalog needs: the metadata and a cover.png.
    private static var catalog = false

    private static func say(_ s: String) { print(s) }

    private static func run(_ dir: URL, out: String?, cover: Bool = false) -> Int32 {
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("pack.json").path) else {
            say("✗ \(dir.path): no pack.json here"); return 2
        }
        Packs.loadOnly(dir)
        var failures = 0
        for p in Packs.problems { say("✗ \(p)"); failures += 1 }
        if catalog, let p = Packs.loaded.first {
            for k in Packs.catalogFields where (p.meta[k] ?? "").isEmpty { say("✗ catalog: pack.json needs \"\(k)\""); failures += 1 }
            if let v = p.meta["version"], v.range(of: #"^\d+(\.\d+){0,2}$"#, options: .regularExpression) == nil {
                say("✗ catalog: \"version\" is numbers like 1.0 or 1.2.3"); failures += 1
            }
            if p.id.range(of: #"^[a-z0-9][a-z0-9_-]{0,40}$"#, options: .regularExpression) == nil {
                say("✗ catalog: the id is lowercase letters, digits, - and _"); failures += 1
            }
            if !FileManager.default.fileExists(atPath: dir.appendingPathComponent("cover.png").path) {
                say("✗ catalog: no cover.png (make it with: fishbots pack cover <folder>)"); failures += 1
            }
        }
        let device = offline ? nil : MTLCreateSystemDefaultDevice()
        if device == nil && !offline { say("  (no Metal device here: compiling with xcrun metal)") }

        // compile each piece alone, and point at its own file and line when it fails
        func check(_ what: String, _ name: String, _ src: String, _ full: String) -> Bool {
            do {
                if let device { _ = try device.makeLibrary(source: full, options: nil) } else { try compileOffline(full) }
                return true
            } catch {
                let start = full.components(separatedBy: "\n").firstIndex { src.hasPrefix($0) && !$0.isEmpty } ?? 0
                let file = fileName(for: src, in: dir)
                say("✗ \(what) \(name) doesn't compile:")
                var seen = Set<String>()
                for line in "\(error)".components(separatedBy: "\n") where line.contains("error:") {
                    // …program_source:LINE:COL: error: …
                    guard let r = line.range(of: "program_source:") else { if seen.insert(line).inserted { say("    " + line) }; continue }
                    let parts = line[r.upperBound...].components(separatedBy: ":")
                    let msg = parts.count > 2 && Int(parts[0]) != nil
                        ? "\(file):\(Int(parts[0])! - start):\(parts[1]):" + parts[2...].joined(separator: ":") : String(line)
                    if seen.insert(msg).inserted { say("    " + msg) }
                }
                failures += 1
                return false
            }
        }
        for k in FishKinds.all where k.pack != nil {
            if !check("fish", k.id, k.source ?? "", FishKinds.shaderSource(testing: k)) { Packs.fishFailed(k, ""); FishKinds.drop(k.id) }
        }
        for k in SceneryKinds.all where !check("scenery", k.id, k.source, FishKinds.shaderSource(testing: k)) { Packs.sceneryFailed(k, ""); SceneryKinds.drop(k.id) }
        for k in FaunaKinds.all where !check("creature", k.id, k.source, FishKinds.shaderSource(testing: k)) { Packs.faunaFailed(k, ""); FaunaKinds.drop(k.id) }
        for k in PackBackgrounds.all where !check("background of", k.id, k.source, FishKinds.shaderSource(testing: k)) {
            Packs.backgroundFailed(k, ""); PackBackgrounds.blank(k.id)
        }
        for k in PackPresences.all where !check("presence", k.id, k.source, FishKinds.shaderSource(testing: k)) {
            Packs.presenceFailed(k, ""); PackPresences.all.removeAll { $0.id == k.id }
        }

        let p = Packs.loaded.first
        say((failures == 0 ? "✓ " : "• ") + (p.map { "\($0.name) (\($0.id)): " + ($0.contents.isEmpty ? "nothing" : $0.contents.joined(separator: ", ")) } ?? "no pack"))
        if let out {
            guard let device else { say("✗ drawing the preview needs a Metal device"); return 2 }
            if cover { drawCover(device, to: out) } else { draw(device, to: out) }
        }
        return failures == 0 ? 0 : 1
    }

    /// Compiles with the offline Metal compiler; throws its error text (with "program_source:" lines, like the GPU's).
    static func compileOffline(_ src: String) throws {
        struct Failure: Error, CustomStringConvertible { let description: String }
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("fishbots-check-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("program_source.metal")
        try src.write(to: file, atomically: true, encoding: .utf8)
        let p = Process(), err = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["-sdk", "macosx", "metal", "-c", file.path, "-o", tmp.appendingPathComponent("out.air").path]
        p.standardError = err
        p.standardOutput = Pipe()
        try p.run()
        let text = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            // "/…/program_source.metal:12:3: error: …" → "program_source:12:3: error: …"
            throw Failure(description: text.replacingOccurrences(of: file.path, with: "program_source"))
        }
    }

    /// cover.png for the catalog: the pack's first theme and drawings in a strip (900 × 200).
    private static func drawCover(_ device: MTLDevice, to out: String) {
        let cs = cells().filter { !$0.label.hasSuffix("asleep") && !$0.label.hasSuffix("glowing") && !$0.label.hasSuffix("night") }
        var pick: [Cell] = []
        if let t = cs.first(where: { $0.label.hasPrefix("theme ") }) { pick.append(t) }
        var seen = Set<String>()
        for c in cs where !c.label.hasPrefix("theme ") {
            let id = c.label.components(separatedBy: " · ").first ?? c.label
            if seen.insert(id).inserted { pick.append(c) }
            if pick.count == 6 { break }
        }
        guard !pick.isEmpty else { say("  (nothing to draw)"); return }
        if render(device, pick.map { Cell(call: $0.call, aspect: $0.aspect, label: "", sand: $0.sand) }, cellW: 300, labels: false,
                  scale: 1, cols: min(3, pick.count), maxRows: 2, to: out) { say("  cover: \(out)") }
    }

    /// Which of the pack's .metal files a source came from (for the error lines).
    private static func fileName(for src: String, in dir: URL) -> String {
        for f in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where f.hasSuffix(".metal") {
            if (try? String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)) == src { return f }
        }
        return "?"
    }

    struct Cell { let call: String; let aspect: Float; let label: String; let sand: Bool }

    /// A small tank in a theme's colors: water from deep to shallow, rays, the surface, seaweed and sand.
    private static func themeCells() -> [Cell] { Packs.themeIds.map { themeCell(Themes.named($0)) } }

    private static func themeCell(_ t: Theme) -> Cell {
        let u = t.uniforms
        func v(_ c: SIMD4<Float>) -> String { "float3(\(c.x), \(c.y), \(c.z))" }
        let call = "pv_theme(c, \(v(u.deep)), \(v(u.shallow)), \(v(u.rays)), \(v(u.surface)), \(v(u.weedLow)), \(v(u.weedHigh)), \(v(u.sandDark)), \(v(u.sandLight)), \(v(u.farWeed)), \(u.params.z), \(Int(u.pack.x + 0.5) - 1))"
        return Cell(call: call, aspect: 1.5, label: "theme \(t.name)", sand: false)
    }

    /// A small picture of each theme (water, light, seaweed, sand and its own background), for the Tema menu: one
    /// render for all of them, cut into pieces. Prepare on the main thread (it reads the registries), draw anywhere
    /// (it compiles the shader, which takes a moment).
    /// A fish drawn big for its card (CardGlass): its kind in its color, pattern and fin cut, on a bit of water.
    /// The job is made on the main thread (it reads the kinds); drawing it can happen anywhere.
    struct PortraitJob { let cell: Cell; let base: String }
    static func portraitJob(species: Int, color c: SIMD3<Float>, pattern: Int, cut: Int) -> PortraitJob {
        let k = FishKinds.all[species]
        let call = "draw_kind(\(species), c, 1.3, 0.1, float4(\(c.x), \(c.y), \(c.z), 1), float4(1, \(pattern + cut * 8), \(species), 0.2), float4(0.4, 0.1, 0, 0))"
        return PortraitJob(cell: Cell(call: call, aspect: k.swim.extent.x / k.swim.extent.y, label: "", sand: false), base: FishKinds.shaderSource())
    }
    static func portrait(_ job: PortraitJob) -> CGImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return renderImage(device, [job.cell], cellW: 252, labels: false, scale: 1, cols: 1, maxRows: 1, base: job.base)
    }

    struct SwatchJob { let ids: [String]; let cells: [Cell]; let base: String; let cellW: Int }
    static func swatchJob(_ themes: [Theme], cellW: Int = 120) -> SwatchJob {
        SwatchJob(ids: themes.map(\.id), cells: themes.map(themeCell), base: FishKinds.shaderSource(), cellW: cellW)
    }
    static func themeSwatches(_ job: SwatchJob) -> [String: CGImage] {
        guard !job.ids.isEmpty, let device = MTLCreateSystemDefaultDevice(),
              let img = renderImage(device, job.cells, cellW: job.cellW, labels: false, scale: 1, cols: job.ids.count, base: job.base) else { return [:] }
        let themes = job.ids.map { (id: $0, 0) }
        var out: [String: CGImage] = [:]
        for (i, t) in themes.enumerated() {
            if let piece = img.cropping(to: CGRect(x: i * job.cellW, y: 0, width: job.cellW, height: job.cellW * 2 / 3)) { out[t.id] = piece }
        }
        return out
    }

    /// Each fish, piece of scenery and creature in six moments (phase or time), to see that it moves.
    private static func motionCells() -> [Cell] {
        var out: [Cell] = []
        let frames: [Float] = [0, 0.6, 1.2, 1.8, 2.4, 3.0]
        for k in FishKinds.all where k.pack != nil {
            let i = FishKinds.index(of: k.id)
            for (n, f) in frames.enumerated() {
                out.append(Cell(call: "draw_kind(\(i), c, \(f), 0.0, float4(0.92, 0.32, 0.2, 1), float4(1, 0, \(i), 0.2), float4(0))",
                                aspect: k.swim.extent.x / k.swim.extent.y, label: n == 0 ? "\(k.id)" : "\(f)", sand: false))
            }
        }
        for (i, k) in SceneryKinds.all.enumerated() {
            for (n, f) in frames.enumerated() {
                out.append(Cell(call: "draw_scenery_pack(\(i), c, \(f * 2), 0.0, float4(\(k.color.x), \(k.color.y), \(k.color.z), 1), float4(1, 0.4, \(i), 0))",
                                aspect: k.extent.x / k.extent.y, label: n == 0 ? "\(k.id)" : "\(f * 2) s", sand: k.anchor == .sand))
            }
        }
        for (i, k) in FaunaKinds.all.enumerated() {
            for (n, f) in frames.enumerated() {
                out.append(Cell(call: "draw_fauna_pack(\(i), c, \(f), 0.0, float4(\(k.color.x), \(k.color.y), \(k.color.z), 1), float4(1, 0.37, \(i), 1))",
                                aspect: k.extent.x / k.extent.y, label: n == 0 ? "\(k.id)" : "\(f)",
                                sand: k.behavior == .crawl || k.behavior == .rest))
            }
        }
        return out
    }

    private static func cells() -> [Cell] {
        var out: [Cell] = themeCells()
        let palette = ["float4(0.92, 0.32, 0.2, 1)", "float4(0.3, 0.6, 0.95, 1)", "float4(0.95, 0.75, 0.3, 1)", "float4(0.5, 0.85, 0.5, 1)"]
        for k in FishKinds.all where k.pack != nil {
            let i = FishKinds.index(of: k.id)
            for v in 0..<4 {
                out.append(Cell(call: "draw_kind(\(i), c, 1.3, 0.0, \(palette[v]), float4(1, \(v), \(i), 0.2), float4(0.5, 0.2, 0, 0))",
                                aspect: k.swim.extent.x / k.swim.extent.y, label: "\(k.id) · pattern \(v)", sand: false))
            }
            out.append(Cell(call: "draw_kind(\(i), c, 1.3, 0.0, \(palette[0]), float4(1, 0, \(i), 2.2), float4(0))",
                            aspect: k.swim.extent.x / k.swim.extent.y, label: "\(k.id) · asleep", sand: false))
            out.append(Cell(call: "draw_kind(\(i), c, 1.3, 0.8, \(palette[1]), float4(1, 0, \(i), 0.2), float4(0))",
                            aspect: k.swim.extent.x / k.swim.extent.y, label: "\(k.id) · glowing", sand: false))
        }
        for (i, k) in SceneryKinds.all.enumerated() {
            let col = "float4(\(k.color.x), \(k.color.y), \(k.color.z), 1)"
            for (night, seed) in [(0, 0.2), (0, 0.7), (1, 0.45)] {
                out.append(Cell(call: "draw_scenery_pack(\(i), c, 2.0, \(k.glowAtNight && night == 1 ? 1 : 0).0, \(col) * float4(float3(\(night == 1 ? 0.55 : 1.0)), 1), float4(1, \(seed), \(i), \(night).0))",
                                aspect: k.extent.x / k.extent.y, label: "\(k.id) · \(night == 1 ? "night" : "seed \(seed)")", sand: k.anchor == .sand))
            }
        }
        for (i, k) in FaunaKinds.all.enumerated() {
            let col = "float4(\(k.color.x), \(k.color.y), \(k.color.z), 1)"
            for (moving, phase) in [(1, 0.5), (1, 2.1), (0, 1.0)] {
                out.append(Cell(call: "draw_fauna_pack(\(i), c, \(phase), 0.0, \(col), float4(1, 0.37, \(i), \(moving).0))",
                                aspect: k.extent.x / k.extent.y, label: "\(k.id) · \(moving == 1 ? "moving" : "resting")",
                                sand: k.behavior == .crawl || k.behavior == .rest))
            }
        }
        for (i, pr) in PackPresences.all.enumerated() {
            guard let k = Scene.kinds[pr.id] else { continue }
            let col = "float4(\(k.color.x), \(k.color.y), \(k.color.z), 1)"
            for (state, name, value) in [(3, "ok", 1.0), (1, "busy", 0.6), (5, "error", 0.3), (2, "waiting", 0.8)] {
                out.append(Cell(call: "draw_presence_pack(\(i), c, 1.3, \(state == 2 ? 0.6 : 0.0), \(col), float4(1, \(value), \(i), \(state)))",
                                aspect: k.extent.x / k.extent.y, label: "\(pr.id) · \(name)", sand: k.motion.grounded))
            }
        }
        return out
    }

    /// Two sheets: big cells with labels (out), and the same at about the real size, enlarged 4× (out-small.png).
    private static func draw(_ device: MTLDevice, to out: String) {
        let cs = cells()
        guard !cs.isEmpty else { say("  (nothing to draw)"); return }
        let base = (out as NSString).deletingPathExtension
        if render(device, cs, cellW: 300, labels: true, scale: 1, to: out) { say("  sheet: \(out)") }
        let drawings = cs.filter { !$0.label.hasPrefix("theme ") }
        if render(device, drawings, cellW: 40, labels: false, scale: 4, to: base + "-small.png") { say("  real size (4×): \(base)-small.png") }
        let motion = motionCells()
        if !motion.isEmpty, render(device, motion, cellW: 200, labels: true, scale: 1, to: base + "-motion.png") {
            say("  motion (6 moments each, left to right; fish and creatures by phase 0…3, scenery by time 0…6 s): \(base)-motion.png")
        }
    }

    private static func render(_ device: MTLDevice, _ cs: [Cell], cellW: Int, labels: Bool, scale: Int, cols: Int = 6, maxRows: Int = 1000,
                               to path: String) -> Bool {
        guard let final = renderImage(device, cs, cellW: cellW, labels: labels, scale: scale, cols: cols, maxRows: maxRows),
              let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dst, final, nil)
        return CGImageDestinationFinalize(dst)
    }

    private static func renderImage(_ device: MTLDevice, _ cs: [Cell], cellW: Int, labels: Bool, scale: Int, cols: Int = 6,
                                    maxRows: Int = 1000, base: String? = nil) -> CGImage? {
        let cellH = cellW * 2 / 3, rows = min(maxRows, (cs.count + cols - 1) / cols)
        var sw = ""
        for (i, c) in cs.enumerated() {
            sw += "    case \(i): { float asp = \(c.aspect) / \(Float(cellW) / Float(cellH)); if (asp < 1.0) c.x /= asp; else c.y *= asp; c *= 1.1;"
            sw += " sand = \(c.sand ? "1.0" : "0.0") * step(c.y, -0.9); o = \(c.call); break; }\n"
        }
        let src = (base ?? FishKinds.shaderSource()) + """

        float4 pv_theme(float2 c, float3 deep, float3 shallow, float3 rays, float3 surf, float3 wl, float3 wh,
                        float3 sd, float3 sl, float3 far, float raysK, int bg) {
            float2 uv = clamp(c * 0.5 + 0.5, 0.0, 1.0);
            float3 col = mix(deep, shallow, pow(uv.y, 1.3));
            float r = pow(sin((uv.x + uv.y * 0.35) * 9.0) * 0.5 + 0.5, 3.0) * smoothstep(0.1, 1.0, uv.y);
            col += rays * r * raysK * 1.5;
            col = mix(col, surf, (1.0 - smoothstep(0.0, 0.015, abs(uv.y - 0.94 - 0.01 * sin(uv.x * 30.0)))) * 0.8);
            col = mix(col, deep * 0.9, step(0.95, uv.y) * 0.5);
            if (bg >= 0) {
                float sandLine = 0.17 + 0.02 * sin(uv.x * 7.0);
                float4 b = draw_background_pack(bg, uv, 2.0, 1.0, float2(0.0), col, float4(1.5, 0.0, sandLine, 0.0));
                col = col * (1.0 - b.a) + b.rgb;
            }
            for (int k = 0; k < 7; k++) {
                float x0 = 0.08 + float(k) * 0.14, h = 0.35 + 0.3 * fract(float(k) * 0.618);
                float yy = uv.y - 0.15, t = clamp(yy / h, 0.0, 1.0);
                float dx = uv.x - x0 - sin(yy * 12.0 + float(k)) * 0.015 * t;
                float blade = (1.0 - smoothstep(0.006, 0.011, abs(dx) / (1.0 - 0.6 * t))) * step(0.0, yy) * step(yy, h);
                col = mix(col, k % 2 == 0 ? mix(wl, wh, t) : far, blade * (k % 2 == 0 ? 0.9 : 0.5));
            }
            float sandH = 0.17 + 0.02 * sin(uv.x * 7.0);
            float3 sand = mix(sd, sl, vnoise(uv * float2(26.0, 14.0)) * 0.6 + vnoise(uv * float2(70.0, 40.0)) * 0.4) * mix(0.65, 1.0, clamp(uv.y / sandH, 0.0, 1.0));
            col = mix(sand, col, smoothstep(sandH - 0.005, sandH, uv.y));
            return float4(col, 1.0);
        }

        struct PvOut { float4 position [[position]]; };
        vertex PvOut pv_vertex(uint vid [[vertex_id]]) {
            float2 p[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
            PvOut o; o.position = float4(p[vid], 0, 1); return o;
        }
        fragment float4 pv_fragment(PvOut in [[stage_in]]) {
            float2 cell = float2(\(cellW).0, \(cellH).0);
            int cx = int(in.position.x / cell.x), cy = int(in.position.y / cell.y);
            int i = cy * \(cols) + cx;
            float2 l = (in.position.xy - float2(cx, cy) * cell) / cell;
            float2 c = float2(l.x * 2.0 - 1.0, 1.0 - l.y * 2.0);
            float3 bg = mix(float3(0.05, 0.14, 0.17), float3(0.09, 0.24, 0.27), l.y);
            float4 o = float4(0.0);
            float sand = 0.0;
            switch (i) {
        \(sw)    default: break;
            }
            bg = mix(bg, float3(0.42, 0.37, 0.28), sand);
            return float4(bg * (1.0 - o.a) + o.rgb, 1.0);
        }
        """
        do {
            let lib = try device.makeLibrary(source: src, options: nil)
            let pd = MTLRenderPipelineDescriptor()
            pd.vertexFunction = lib.makeFunction(name: "pv_vertex")
            pd.fragmentFunction = lib.makeFunction(name: "pv_fragment")
            pd.colorAttachments[0].pixelFormat = .rgba8Unorm
            let pso = try device.makeRenderPipelineState(descriptor: pd)
            let W = cellW * cols, H = cellH * rows
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: W, height: H, mipmapped: false)
            td.usage = [.renderTarget]; td.storageMode = .shared
            guard let tex = device.makeTexture(descriptor: td), let q = device.makeCommandQueue(), let cb = q.makeCommandBuffer() else { return nil }
            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture = tex; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
            guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return nil }
            enc.setRenderPipelineState(pso)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding(); cb.commit(); cb.waitUntilCompleted()
            var bytes = [UInt8](repeating: 0, count: W * H * 4)
            tex.getBytes(&bytes, bytesPerRow: W * 4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0)
            guard let src = CGContext(data: &bytes, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
                  let img = src.makeImage(),
                  let ctx = CGContext(data: nil, width: W * scale, height: H * scale, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            ctx.interpolationQuality = .none
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: W * scale, height: H * scale))
            if labels {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(white: 1, alpha: 0.75)]
                for (i, c) in cs.enumerated() {
                    let x = (i % cols) * cellW + 8, y = H - (i / cols + 1) * cellH + 6
                    (c.label as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
                }
                NSGraphicsContext.restoreGraphicsState()
            }
            return ctx.makeImage()
        } catch {
            say("✗ the sheet didn't compile: \(error)")
            return nil
        }
    }
}
