import CoreGraphics
import Foundation
import Metal
import simd

/// Drawings rendered off screen with the aquarium's own shader: cells side by side, each one a call into the shader
/// (a fish, a piece of scenery, a theme's water). The fish cards' portraits, the theme menu's swatches and the pack
/// preview sheets.
enum ShaderSheet {
    struct Cell { let call: String; let aspect: Float; let label: String; let sand: Bool }
    /// Told when a sheet doesn't render (the shader didn't compile, no texture): the app logs it.
    static var failed: ((String) -> Void)? = { FileHandle.standardError.write("fishbots: \($0)\n".data(using: .utf8)!) }

    static func render(_ device: MTLDevice, _ cs: [Cell], cellW: Int, scale: Int = 1, cols: Int = 6, maxRows: Int = 1000,
                       base: String? = nil, overlay: ((CGContext, _ width: Int, _ height: Int) -> Void)? = nil) -> CGImage? {
        let cellH = cellW * 2 / 3, rows = min(maxRows, (cs.count + cols - 1) / cols)
        var sw = ""
        for (i, c) in cs.enumerated() {
            sw += "    case \(i): { float asp = \(c.aspect) / \(Float(cellW) / Float(cellH)); if (asp < 1.0) c.x /= asp; else c.y *= asp; c *= 1.1;"
            sw += " sand = \(c.sand ? "1.0" : "0.0") * step(c.y, -0.9); o = \(c.call); break; }\n"
        }
        let src = (base ?? FishKinds.shaderSource()) + """

        float4 pv_theme(float2 c, float3 deep, float3 shallow, float3 rays, float3 surf, float3 wl, float3 wh,
                        float3 sd, float3 sl, float3 far, float raysK, int bg, float weeds, float floorOn, float surfOn) {
            float2 uv = clamp(c * 0.5 + 0.5, 0.0, 1.0);
            float3 col = mix(deep, shallow, pow(uv.y, 1.3));
            float r = pow(sin((uv.x + uv.y * 0.35) * 9.0) * 0.5 + 0.5, 3.0) * smoothstep(0.1, 1.0, uv.y);
            col += rays * r * raysK * 1.5;
            col = mix(col, surf, (1.0 - smoothstep(0.0, 0.015, abs(uv.y - 0.94 - 0.01 * sin(uv.x * 30.0)))) * 0.8 * surfOn);
            col = mix(col, deep * 0.9, step(0.95, uv.y) * 0.5 * surfOn);                                       // (a sky: no surface)
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
                col = mix(col, k % 2 == 0 ? mix(wl, wh, t) : far, blade * (k % 2 == 0 ? 0.9 : 0.5) * weeds);   // (a theme with no seaweed: none)
            }
            float sandH = 0.17 + 0.02 * sin(uv.x * 7.0);
            float3 sand = mix(sd, sl, vnoise(uv * float2(26.0, 14.0)) * 0.6 + vnoise(uv * float2(70.0, 40.0)) * 0.4) * mix(0.65, 1.0, clamp(uv.y / sandH, 0.0, 1.0));
            col = mix(sand, col, max(smoothstep(sandH - 0.005, sandH, uv.y), 1.0 - floorOn));                    // (and with no floor: no sand)
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
            guard let tex = device.makeTexture(descriptor: td), let q = device.makeCommandQueue(), let cb = q.makeCommandBuffer() else {
                failed?("the sheet got no texture (\(W)×\(H))"); return nil
            }
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
            overlay?(ctx, W, H)
            return ctx.makeImage()
        } catch {
            failed?("the sheet didn't compile: \(error)")
            return nil
        }
    }
}

/// Each fish drawn big, as the tank draws it (its kind, color, pattern and fin cut), on a bit of water. Drawing one
/// compiles the shader, so it happens once per look, in the background; the card asks again when it's ready.
enum FishPortraits {
    private static var cache: [String: CGImage] = [:]
    private static var pending = Set<String>()

    /// The picture, if it's been drawn; otherwise nil now and `ready` (on the main thread) once it has.
    static func image(for f: Fish, ready: @escaping () -> Void) -> CGImage? {
        guard FishKinds.all.indices.contains(f.species) else { return nil }
        let c = f.color
        let key = "\(f.kindID)|\(f.species)|\(f.pattern)|\(f.cut)|\(c.x),\(c.y),\(c.z)|\(FishKinds.all.count)"
        if let img = cache[key] { return img }
        guard pending.insert(key).inserted else { return nil }
        let job = portraitJob(species: f.species, color: c, pattern: f.pattern, cut: f.cut)
        DispatchQueue.global(qos: .utility).async {
            let img = portrait(job)
            DispatchQueue.main.async {
                pending.remove(key)
                guard let img else { return }
                if cache.count > 60 { cache.removeAll() }       // packs came and went: start over
                cache[key] = img
                ready()
            }
        }
        return nil
    }

    /// A fish drawn big for its card: its kind in its color, pattern and fin cut, on a bit of water.
    /// The job is made on the main thread (it reads the kinds); drawing it can happen anywhere.
    struct PortraitJob { let cell: ShaderSheet.Cell; let base: String }
    static func portraitJob(species: Int, color c: SIMD3<Float>, pattern: Int, cut: Int) -> PortraitJob {
        let k = FishKinds.all[species]
        let call = "draw_kind(\(species), c, 1.3, 0.1, float4(\(c.x), \(c.y), \(c.z), 1), float4(1, \(pattern + cut * 8), \(species), 0.2), float4(0.4, 0.1, 0, 0))"
        return PortraitJob(cell: ShaderSheet.Cell(call: call, aspect: k.swim.extent.x / k.swim.extent.y, label: "", sand: false), base: FishKinds.shaderSource())
    }
    static func portrait(_ job: PortraitJob) -> CGImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return ShaderSheet.render(device, [job.cell], cellW: 252, cols: 1, maxRows: 1, base: job.base)
    }
}
