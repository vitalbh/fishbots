// Draws the app icon (a cute fish with a little robot antenna, in a tank) and builds Resources/AppIcon.icns.
//   swift scripts/make-icon.swift            (from the repository root)
//   swift scripts/make-icon.swift --ios      the iPhone's: the same tank filling an opaque square (iOS rounds it)
import AppKit

let S: CGFloat = 1024
let square = CommandLine.arguments.contains("--ios")

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

func draw(_ ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // the macOS icon shape: a rounded square on the 1024 grid (824 wide, centered)
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    // the iPhone's is a plain square: iOS rounds it, and draws no outline
    let shape = square ? CGPath(rect: tile, transform: nil) : CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // drop shadow under the tile
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(color(0x0b2f4a)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()

    // water: turquoise near the surface, deep blue at the bottom
    let water = CGGradient(colorsSpace: space, colors: [color(0x2fb6c9), color(0x137a9a), color(0x08304f)] as CFArray, locations: [0, 0.45, 1])!
    ctx.drawLinearGradient(water, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])

    // light rays from the surface
    for (x, w, a) in [(300.0, 70.0, 0.10), (470.0, 110.0, 0.08), (690.0, 60.0, 0.10)] as [(CGFloat, CGFloat, CGFloat)] {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x, y: tile.maxY))
        p.addLine(to: CGPoint(x: x + w, y: tile.maxY))
        p.addLine(to: CGPoint(x: x + w - 160, y: tile.minY + 160))
        p.addLine(to: CGPoint(x: x - 160, y: tile.minY + 160))
        p.closeSubpath()
        ctx.saveGState()
        ctx.addPath(p); ctx.clip()
        let ray = CGGradient(colorsSpace: space, colors: [color(0xffffff, a), color(0xffffff, 0)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(ray, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY + 200), options: [])
        ctx.restoreGState()
    }

    // surface wave
    let surface = CGMutablePath()
    surface.move(to: CGPoint(x: tile.minX, y: 842))
    for i in 0...20 {
        let x = tile.minX + CGFloat(i) / 20 * tile.width
        surface.addLine(to: CGPoint(x: x, y: 842 + 10 * sin(CGFloat(i) * 0.9)))
    }
    surface.addLine(to: CGPoint(x: tile.maxX, y: tile.maxY)); surface.addLine(to: CGPoint(x: tile.minX, y: tile.maxY)); surface.closeSubpath()
    ctx.addPath(surface); ctx.setFillColor(color(0xbff4ff, 0.22)); ctx.fillPath()

    // seaweed
    func blade(_ x: CGFloat, _ h: CGFloat, _ lean: CGFloat, _ c: UInt32) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x - 16, y: 180))
        p.addCurve(to: CGPoint(x: x + lean, y: 180 + h), control1: CGPoint(x: x - 40, y: 180 + h * 0.4), control2: CGPoint(x: x + lean + 30, y: 180 + h * 0.7))
        p.addCurve(to: CGPoint(x: x + 16, y: 180), control1: CGPoint(x: x + lean + 10, y: 180 + h * 0.6), control2: CGPoint(x: x + 30, y: 180 + h * 0.3))
        p.closeSubpath()
        ctx.addPath(p); ctx.setFillColor(color(c)); ctx.fillPath()
    }
    blade(200, 330, 30, 0x2f8a52); blade(245, 240, -20, 0x3fa462)
    blade(810, 300, -40, 0x2f8a52); blade(770, 200, 20, 0x46b06a)

    // sand
    let sand = CGMutablePath()
    sand.move(to: CGPoint(x: tile.minX, y: 230))
    sand.addCurve(to: CGPoint(x: tile.maxX, y: 210), control1: CGPoint(x: 350, y: 285), control2: CGPoint(x: 650, y: 170))
    sand.addLine(to: CGPoint(x: tile.maxX, y: tile.minY)); sand.addLine(to: CGPoint(x: tile.minX, y: tile.minY)); sand.closeSubpath()
    ctx.saveGState()
    ctx.addPath(sand); ctx.clip()
    let sandG = CGGradient(colorsSpace: space, colors: [color(0xe8cf98), color(0xb8915a)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sandG, start: CGPoint(x: 0, y: 280), end: CGPoint(x: 0, y: tile.minY), options: [])
    ctx.restoreGState()
    for (x, y, r) in [(330.0, 190.0, 9.0), (420.0, 215.0, 7.0), (610.0, 180.0, 8.0), (700.0, 200.0, 6.0)] as [(CGFloat, CGFloat, CGFloat)] {
        ctx.setFillColor(color(0xfff5e0, 0.8)); ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    // bubbles
    for (x, y, r) in [(735.0, 610.0, 22.0), (770.0, 690.0, 15.0), (748.0, 755.0, 10.0)] as [(CGFloat, CGFloat, CGFloat)] {
        let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
        ctx.setFillColor(color(0xffffff, 0.18)); ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(color(0xffffff, 0.75)); ctx.setLineWidth(3.5); ctx.strokeEllipse(in: rect)
        ctx.setFillColor(color(0xffffff, 0.9)); ctx.fillEllipse(in: CGRect(x: x - r * 0.45, y: y + r * 0.2, width: r * 0.4, height: r * 0.4))
    }

    // the fish (facing right), centered a bit low
    let c = CGPoint(x: 490, y: 500)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0x02121f, 0.45))
    // tail
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: c.x - 170, y: c.y))
    tail.addCurve(to: CGPoint(x: c.x - 300, y: c.y + 120), control1: CGPoint(x: c.x - 220, y: c.y + 40), control2: CGPoint(x: c.x - 270, y: c.y + 110))
    tail.addCurve(to: CGPoint(x: c.x - 300, y: c.y - 120), control1: CGPoint(x: c.x - 250, y: c.y + 30), control2: CGPoint(x: c.x - 250, y: c.y - 30))
    tail.addCurve(to: CGPoint(x: c.x - 170, y: c.y), control1: CGPoint(x: c.x - 270, y: c.y - 110), control2: CGPoint(x: c.x - 220, y: c.y - 40))
    ctx.addPath(tail); ctx.setFillColor(color(0xff7a59)); ctx.fillPath()
    // dorsal fin
    let fin = CGMutablePath()
    fin.move(to: CGPoint(x: c.x - 90, y: c.y + 140))
    fin.addCurve(to: CGPoint(x: c.x + 60, y: c.y + 150), control1: CGPoint(x: c.x - 60, y: c.y + 250), control2: CGPoint(x: c.x + 40, y: c.y + 230))
    fin.closeSubpath()
    ctx.addPath(fin); ctx.setFillColor(color(0xff6b5e)); ctx.fillPath()
    // body
    let body = CGRect(x: c.x - 220, y: c.y - 165, width: 440, height: 330)
    ctx.addEllipse(in: body)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: body); ctx.clip()
    let bodyG = CGGradient(colorsSpace: space, colors: [color(0xffb36b), color(0xff7a59), color(0xf0506e)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bodyG, start: CGPoint(x: c.x, y: body.maxY), end: CGPoint(x: c.x, y: body.minY), options: [])
    // white band (like a neon's stripe), and a soft belly
    let band = CGMutablePath()                                       // curved, following the body
    band.addEllipse(in: CGRect(x: c.x - 70, y: body.minY - 40, width: 110, height: body.height + 80))
    band.addEllipse(in: CGRect(x: c.x - 30, y: body.minY - 40, width: 110, height: body.height + 80))
    ctx.saveGState()
    ctx.addPath(band); ctx.clip(using: .evenOdd)
    ctx.setFillColor(color(0xffffff, 0.93)); ctx.fill(CGRect(x: c.x - 70, y: body.minY, width: 50, height: body.height))
    ctx.restoreGState()
    let belly = CGGradient(colorsSpace: space, colors: [color(0xfff1d6, 0.28), color(0xfff1d6, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(belly, startCenter: CGPoint(x: c.x + 20, y: body.minY + 40), startRadius: 0,
                           endCenter: CGPoint(x: c.x + 20, y: body.minY + 40), endRadius: 170, options: [])
    // gloss on top
    let gloss = CGGradient(colorsSpace: space, colors: [color(0xffffff, 0.45), color(0xffffff, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(gloss, startCenter: CGPoint(x: c.x + 30, y: c.y + 110), startRadius: 0,
                           endCenter: CGPoint(x: c.x + 30, y: c.y + 110), endRadius: 170, options: [])
    ctx.restoreGState()
    // side fin
    let side = CGMutablePath()
    side.move(to: CGPoint(x: c.x - 10, y: c.y - 40))
    side.addCurve(to: CGPoint(x: c.x - 100, y: c.y - 110), control1: CGPoint(x: c.x - 40, y: c.y - 60), control2: CGPoint(x: c.x - 90, y: c.y - 70))
    side.addCurve(to: CGPoint(x: c.x - 10, y: c.y - 40), control1: CGPoint(x: c.x - 60, y: c.y - 120), control2: CGPoint(x: c.x - 20, y: c.y - 80))
    ctx.addPath(side); ctx.setFillColor(color(0xe2475f, 0.85)); ctx.fillPath()

    // the robot antenna: a little stalk with a glowing tip
    let base = CGPoint(x: c.x + 110, y: c.y + 140)
    let tip = CGPoint(x: c.x + 150, y: c.y + 270)
    let stalk = CGMutablePath()
    stalk.move(to: base); stalk.addQuadCurve(to: tip, control: CGPoint(x: c.x + 100, y: c.y + 230))
    ctx.addPath(stalk); ctx.setStrokeColor(color(0x37475a)); ctx.setLineWidth(12); ctx.setLineCap(.round); ctx.strokePath()
    let glowG = CGGradient(colorsSpace: space, colors: [color(0xfff59a, 0.9), color(0xffe066, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glowG, startCenter: tip, startRadius: 0, endCenter: tip, endRadius: 80, options: [])
    ctx.setFillColor(color(0xfff7b0)); ctx.fillEllipse(in: CGRect(x: tip.x - 26, y: tip.y - 26, width: 52, height: 52))
    ctx.setFillColor(color(0xffffff)); ctx.fillEllipse(in: CGRect(x: tip.x - 14, y: tip.y + 2, width: 14, height: 14))

    // the eye: big and friendly
    let eye = CGPoint(x: c.x + 120, y: c.y + 30)
    ctx.setFillColor(color(0xffffff)); ctx.fillEllipse(in: CGRect(x: eye.x - 62, y: eye.y - 62, width: 124, height: 124))
    ctx.setFillColor(color(0x1b2533)); ctx.fillEllipse(in: CGRect(x: eye.x - 28, y: eye.y - 36, width: 72, height: 78))
    ctx.setFillColor(color(0xffffff)); ctx.fillEllipse(in: CGRect(x: eye.x + 4, y: eye.y + 10, width: 24, height: 24))
    ctx.setFillColor(color(0xffffff, 0.8)); ctx.fillEllipse(in: CGRect(x: eye.x - 14, y: eye.y - 22, width: 11, height: 11))
    // a little smile and a blush
    let smile = CGMutablePath()
    smile.move(to: CGPoint(x: c.x + 170, y: c.y - 60))
    smile.addQuadCurve(to: CGPoint(x: c.x + 205, y: c.y - 50), control: CGPoint(x: c.x + 192, y: c.y - 78))
    ctx.addPath(smile); ctx.setStrokeColor(color(0x8a2a3c)); ctx.setLineWidth(9); ctx.setLineCap(.round); ctx.strokePath()
    ctx.setFillColor(color(0xff4f7a, 0.35)); ctx.fillEllipse(in: CGRect(x: c.x + 90, y: c.y - 80, width: 60, height: 34))

    // glass: a soft highlight across the top and a thin rim
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let shine = CGGradient(colorsSpace: space, colors: [color(0xffffff, 0.16), color(0xffffff, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(shine, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.maxY - 260), options: [])
    ctx.restoreGState()
    if !square { ctx.addPath(shape); ctx.setStrokeColor(color(0xffffff, 0.18)); ctx.setLineWidth(4); ctx.strokePath() }
}

func png(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(size) / S, y: CGFloat(size) / S)
    ctx.setShouldAntialias(true)
    draw(ctx)
    return rep.representation(using: .png, properties: [:])!
}

if CommandLine.arguments.contains("--ios") {
    let out = "iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(color(0x08304f))
    ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    // the tile (824 wide, from 100) grows to fill the square
    let k = S / 824
    ctx.scaleBy(x: k, y: k)
    ctx.translateBy(x: -100, y: -100)
    draw(ctx)
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dst)
    print(out)
    exit(0)
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for s in [16, 32, 128, 256, 512] {
    try! png(s).write(to: iconset.appendingPathComponent("icon_\(s)x\(s).png"))
    try! png(s * 2).write(to: iconset.appendingPathComponent("icon_\(s)x\(s)@2x.png"))
}
try! fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
try! png(1024).write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Resources/AppIcon.icns" : "iconutil failed")
