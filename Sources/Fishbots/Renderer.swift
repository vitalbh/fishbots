import MetalKit
import simd

struct Uniforms {
    var res: SIMD2<Float>
    var time: Float
    var turbidity: Float
    var light: Float
    var alert: Float
    var pix: SIMD2<Float>
    /// Parallax: where you're "looking" (the mouse, from -1 to 1).
    var gaze: SIMD2<Float> = .zero
    /// Lightning (the scene's effect): how bright the water is, 0…1.
    var flash: Float = 0
    /// The hour's color (Tank.grade): rgb multiplies the image, w is how much moonlight (the rays turn blue).
    var grade: SIMD4<Float> = [1, 1, 1, 0]
    /// The scene's continuous controls, from gauges (docs/scene.md): waves, rain, water temperature (0.5 neutral), fog.
    var scene: SIMD4<Float> = [0, 0, 0.5, 0]
    /// The sun or moon seen through the surface (Tank.sky): x (0…1), how strong, and its warmth (0 cold moon … 1 low sun).
    var sky: SIMD4<Float> = [0.5, 0, 0, 0]
}

struct Sprite {
    var pos: SIMD2<Float>
    var dir: SIMD2<Float>
    var size: Float
    var kind: Float
    var glow: Float
    var phase: Float
    var color: SIMD4<Float>
    var extra: SIMD4<Float>
    /// More per-sprite data. Fish: where the eye looks (xy, in the fish's own axes) and how blurred it is by distance (z).
    var aux: SIMD4<Float> = .zero
}

final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let bgPipeline: MTLRenderPipelineState
    private let spritePipeline: MTLRenderPipelineState
    // bloom: the glow target, reduced to a quarter, blurred and added back on top
    private let downPipeline: MTLRenderPipelineState
    private let blurPipeline: MTLRenderPipelineState
    private let addPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private var glowTex: MTLTexture?
    private var quarterA: MTLTexture?
    private var quarterB: MTLTexture?
    /// The glow target is full size and written by every pass: 8 bits per channel is plenty (values stay within 0…1),
    /// and half the memory traffic of 16. The blur's small textures keep 16 bits (no banding in the soft halos).
    private static let glowTargetFormat = MTLPixelFormat.rgba8Unorm
    private static let glowFormat = MTLPixelFormat.rgba16Float
    /// How strong the bloom is (0: off).
    var bloom: Float = Env.value("BLOOM").flatMap(Float.init) ?? 1.1
    /// FISHBOTS_GPUSTATS=1: prints the average GPU time per frame every 5 s (to measure the shaders).
    private let gpuStats = ProcessInfo.processInfo.environment["FISHBOTS_GPUSTATS"] == "1"
    private var gpuSum: Double = 0
    private var gpuFrames = 0
    private var gpuSince = CACurrentMediaTime()
    private let maxSprites = 4096
    private var buffers: [MTLBuffer] = []
    private var bufIdx = 0
    private let inflight = DispatchSemaphore(value: 3)
    private let t0 = CACurrentMediaTime()
    private var last = CACurrentMediaTime()

    /// Told when the packs' fish didn't compile (the app reports it; see Packs).
    static var packFishFailed: ((FishKind, String) -> Void)?
    static var packSceneryFailed: ((SceneryKind, String) -> Void)?

    /// The scene's colors (see Theme.swift).
    var theme = Theme.classicUniforms
    /// The seaweed: x, height and bend of each blade (Tank.weedUniforms), 16 of them.
    var weeds = [SIMD4<Float>](repeating: .zero, count: 16)

    /// Called every frame with dt; returns uniforms (without size) and sprites.
    var frame: ((Float) -> (Uniforms, [Sprite]))?

    init?(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        precondition(MemoryLayout<Sprite>.stride == 80, "Sprite must be 80 bytes")
        precondition(MemoryLayout<Uniforms>.stride == 96, "Uniforms must be 96 bytes")
        precondition(MemoryLayout<ThemeUniforms>.stride == 192, "ThemeUniforms must be 192 bytes")
        self.device = device
        self.queue = queue
        do {
            let lib: MTLLibrary
            do {
                lib = try device.makeLibrary(source: FishKinds.shaderSource(), options: nil)
            } catch where FishKinds.all.contains(where: { $0.pack != nil }) || !SceneryKinds.all.isEmpty {
                // a pack's fish or scenery broke the shader: try each one alone and drop the ones that don't compile
                for k in FishKinds.all where k.pack != nil {
                    do { _ = try device.makeLibrary(source: FishKinds.shaderSource(testing: k), options: nil) }
                    catch { Renderer.packFishFailed?(k, "\(error)"); FishKinds.drop(k.id) }
                }
                for k in SceneryKinds.all {
                    do { _ = try device.makeLibrary(source: FishKinds.shaderSource(testing: k), options: nil) }
                    catch { Renderer.packSceneryFailed?(k, "\(error)"); SceneryKinds.drop(k.id) }
                }
                lib = try device.makeLibrary(source: FishKinds.shaderSource(), options: nil)
            }
            let bg = MTLRenderPipelineDescriptor()
            bg.vertexFunction = lib.makeFunction(name: "bg_vertex")
            bg.fragmentFunction = lib.makeFunction(name: "bg_fragment")
            bg.colorAttachments[0].pixelFormat = view.colorPixelFormat
            bg.colorAttachments[1].pixelFormat = Self.glowTargetFormat
            bgPipeline = try device.makeRenderPipelineState(descriptor: bg)

            let sp = MTLRenderPipelineDescriptor()
            sp.vertexFunction = lib.makeFunction(name: "sprite_vertex")
            sp.fragmentFunction = lib.makeFunction(name: "sprite_fragment")
            let ca = sp.colorAttachments[0]!
            ca.pixelFormat = view.colorPixelFormat
            ca.isBlendingEnabled = true
            ca.rgbBlendOperation = .add
            ca.alphaBlendOperation = .add
            ca.sourceRGBBlendFactor = .one          // premultiplied color
            ca.sourceAlphaBlendFactor = .one
            ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
            ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            // the glow target blends the same way (what's in front covers the glow behind it)
            let cg = sp.colorAttachments[1]!
            cg.pixelFormat = Self.glowTargetFormat
            cg.isBlendingEnabled = true
            cg.rgbBlendOperation = .add
            cg.alphaBlendOperation = .add
            cg.sourceRGBBlendFactor = .one
            cg.sourceAlphaBlendFactor = .one
            cg.destinationRGBBlendFactor = .oneMinusSourceAlpha
            cg.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            spritePipeline = try device.makeRenderPipelineState(descriptor: sp)

            func post(_ fragment: String, _ format: MTLPixelFormat, additive: Bool = false) throws -> MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = lib.makeFunction(name: "post_vertex")
                d.fragmentFunction = lib.makeFunction(name: fragment)
                d.colorAttachments[0].pixelFormat = format
                if additive {
                    let a = d.colorAttachments[0]!
                    a.isBlendingEnabled = true
                    a.rgbBlendOperation = .add
                    a.alphaBlendOperation = .add
                    a.sourceRGBBlendFactor = .one
                    a.destinationRGBBlendFactor = .one
                    a.sourceAlphaBlendFactor = .zero
                    a.destinationAlphaBlendFactor = .one
                }
                return try device.makeRenderPipelineState(descriptor: d)
            }
            downPipeline = try post("bloom_down", Self.glowFormat)
            blurPipeline = try post("bloom_blur", Self.glowFormat)
            addPipeline = try post("bloom_add", view.colorPixelFormat, additive: true)
            let sd = MTLSamplerDescriptor()
            sd.minFilter = .linear
            sd.magFilter = .linear
            sd.sAddressMode = .clampToEdge
            sd.tAddressMode = .clampToEdge
            guard let smp = device.makeSamplerState(descriptor: sd) else { return nil }
            sampler = smp
        } catch {
            FileHandle.standardError.write("fishbots: shader failed: \(error)\n".data(using: .utf8)!)
            return nil
        }
        for _ in 0..<3 {
            guard let b = device.makeBuffer(length: maxSprites * MemoryLayout<Sprite>.stride, options: .storageModeShared) else { return nil }
            buffers.append(b)
        }
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { glowTex = nil }

    /// The shader's clock (u.time), so the CPU can follow what it draws (the rays lighting the marine snow).
    var shaderTime: Float { Float(CACurrentMediaTime() - t0) }

    /// The bloom's textures, (re)made for the drawable's size.
    private func bloomTextures(_ w: Int, _ h: Int) -> (MTLTexture, MTLTexture, MTLTexture)? {
        if let g = glowTex, g.width == w, g.height == h, let a = quarterA, let b = quarterB { return (g, a, b) }
        func make(_ w: Int, _ h: Int, _ format: MTLPixelFormat = Self.glowFormat) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: max(1, w), height: max(1, h), mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            return device.makeTexture(descriptor: d)
        }
        guard let g = make(w, h, Self.glowTargetFormat), let a = make(w / 4, h / 4), let b = make(w / 4, h / 4) else { return nil }
        glowTex = g; quarterA = a; quarterB = b
        return (g, a, b)
    }

    private func postPass(_ cmd: MTLCommandBuffer, _ pipeline: MTLRenderPipelineState, from src: MTLTexture, to dst: MTLTexture,
                          load: Bool = false, _ setup: (MTLRenderCommandEncoder) -> Void = { _ in }) {
        let d = MTLRenderPassDescriptor()
        d.colorAttachments[0].texture = dst
        d.colorAttachments[0].loadAction = load ? .load : .dontCare
        d.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: d) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(src, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        setup(enc)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    func draw(in view: MTKView) {
        let nowT = CACurrentMediaTime()
        let dt = Float(nowT - last)
        last = nowT
        guard let frame, let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else { return }
        var (u, sprites) = frame(dt)
        u.res = [Float(view.bounds.width), Float(view.bounds.height)]
        u.pix = [Float(view.drawableSize.width), Float(view.drawableSize.height)]
        u.time = Float(nowT - t0)

        inflight.wait()
        let buf = buffers[bufIdx]
        bufIdx = (bufIdx + 1) % buffers.count
        let count = min(sprites.count, maxSprites)
        if count > 0 {
            sprites.withUnsafeBytes { raw in
                buf.contents().copyMemory(from: raw.baseAddress!, byteCount: count * MemoryLayout<Sprite>.stride)
            }
        }

        let dw = Int(view.drawableSize.width), dh = Int(view.drawableSize.height)
        guard let (glow, qa, qb) = bloomTextures(dw, dh) else { inflight.signal(); return }
        pass.colorAttachments[1].texture = glow
        pass.colorAttachments[1].loadAction = .clear
        pass.colorAttachments[1].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[1].storeAction = .store
        guard let cmd = queue.makeCommandBuffer(), let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else {
            inflight.signal()
            return
        }
        enc.setRenderPipelineState(bgPipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        var th = theme
        enc.setFragmentBytes(&th, length: MemoryLayout<ThemeUniforms>.stride, index: 1)
        var wd = weeds.count == 16 ? weeds : Array((weeds + [SIMD4<Float>](repeating: .zero, count: 16)).prefix(16))
        enc.setFragmentBytes(&wd, length: MemoryLayout<SIMD4<Float>>.stride * 16, index: 2)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        if count > 0 {
            enc.setRenderPipelineState(spritePipeline)
            enc.setVertexBuffer(buf, offset: 0, index: 0)
            enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
        }
        enc.endEncoding()

        // bloom: a quarter of the glow, blurred twice each way, added onto the image (with the front glass, always)
        if bloom > 0.001 {
            postPass(cmd, downPipeline, from: glow, to: qa)
            for spread: Float in [1.0, 2.0] {
                var h = SIMD2<Float>(spread, 0), v = SIMD2<Float>(0, spread)
                postPass(cmd, blurPipeline, from: qa, to: qb) { $0.setFragmentBytes(&h, length: MemoryLayout<SIMD2<Float>>.stride, index: 0) }
                postPass(cmd, blurPipeline, from: qb, to: qa) { $0.setFragmentBytes(&v, length: MemoryLayout<SIMD2<Float>>.stride, index: 0) }
            }
        }
        var strength = bloom
        postPass(cmd, addPipeline, from: qa, to: drawable.texture, load: true) {
            $0.setFragmentBytes(&strength, length: MemoryLayout<Float>.stride, index: 0)
            $0.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        }
        cmd.present(drawable)
        let without = inflight
        let stats = gpuStats
        cmd.addCompletedHandler { [weak self] c in
            without.signal()
            guard stats else { return }
            let ms = (c.gpuEndTime - c.gpuStartTime) * 1000
            DispatchQueue.main.async {
                guard let self else { return }
                self.gpuSum += ms; self.gpuFrames += 1
                if CACurrentMediaTime() - self.gpuSince > 5 {
                    let line = String(format: "fishbots gpu: %.2f ms/frame (%d frames)\n", self.gpuSum / Double(max(1, self.gpuFrames)), self.gpuFrames)
                    FileHandle.standardError.write(Data(line.utf8))
                    self.gpuSum = 0; self.gpuFrames = 0; self.gpuSince = CACurrentMediaTime()
                }
            }
        }
        cmd.commit()
    }
}
