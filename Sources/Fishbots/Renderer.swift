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
}

final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let bgPipeline: MTLRenderPipelineState
    private let spritePipeline: MTLRenderPipelineState
    private let maxSprites = 4096
    private var buffers: [MTLBuffer] = []
    private var bufIdx = 0
    private let inflight = DispatchSemaphore(value: 3)
    private let t0 = CACurrentMediaTime()
    private var last = CACurrentMediaTime()

    /// Told when the packs' fish didn't compile (the app reports it; see Packs).
    static var packFishFailed: ((FishKind, String) -> Void)?

    /// The scene's colors (see Theme.swift).
    var theme = Theme.classicUniforms
    /// The seaweed: x, height and bend of each blade (Tank.weedUniforms), 16 of them.
    var weeds = [SIMD4<Float>](repeating: .zero, count: 16)

    /// Called every frame with dt; returns uniforms (without size) and sprites.
    var frame: ((Float) -> (Uniforms, [Sprite]))?

    init?(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        precondition(MemoryLayout<Sprite>.stride == 64, "Sprite must be 64 bytes")
        precondition(MemoryLayout<Uniforms>.stride == 48, "Uniforms must be 48 bytes")
        precondition(MemoryLayout<ThemeUniforms>.stride == 192, "ThemeUniforms must be 192 bytes")
        self.device = device
        self.queue = queue
        do {
            let lib: MTLLibrary
            do {
                lib = try device.makeLibrary(source: FishKinds.shaderSource(), options: nil)
            } catch where FishKinds.all.contains(where: { $0.pack != nil }) {
                // a pack's fish broke the shader: try each one alone and drop the ones that don't compile
                for k in FishKinds.all where k.pack != nil {
                    do { _ = try device.makeLibrary(source: FishKinds.shaderSource(testing: k), options: nil) }
                    catch { Renderer.packFishFailed?(k, "\(error)"); FishKinds.drop(k.id) }
                }
                lib = try device.makeLibrary(source: FishKinds.shaderSource(), options: nil)
            }
            let bg = MTLRenderPipelineDescriptor()
            bg.vertexFunction = lib.makeFunction(name: "bg_vertex")
            bg.fragmentFunction = lib.makeFunction(name: "bg_fragment")
            bg.colorAttachments[0].pixelFormat = view.colorPixelFormat
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
            spritePipeline = try device.makeRenderPipelineState(descriptor: sp)
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

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

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
        cmd.present(drawable)
        let without = inflight
        cmd.addCompletedHandler { _ in without.signal() }
        cmd.commit()
    }
}
