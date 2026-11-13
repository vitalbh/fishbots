import AppKit
import simd

/// The album art of what's playing (Spotify or the Music app): shown on the music fish's card, and its two most
/// striking colors tint the water's light and the aurora while it plays (Preferências → Aparência, on by default).
enum AlbumArt {
    /// The art's two colors (vivid, then a second one that differs), nil when nothing plays or there's no art.
    private(set) static var colors: (SIMD3<Float>, SIMD3<Float>)?
    private static var token = 0

    static var enabled: Bool {
        get { UserDefaults.standard.flag("albumColors") }
        set { UserDefaults.standard.set(newValue, forKey: "albumColors") }
    }

    /// Fetch the current track's art in the background; `done` gets it on the main thread (nil: none).
    static func load(player: String, done: @escaping (CGImage?) -> Void) {
        token += 1
        let mine = token
        DispatchQueue.global(qos: .utility).async {
            let img = player == "Spotify" ? spotify() : music()
            let pal = img.flatMap(palette)
            DispatchQueue.main.async {
                guard mine == token else { return }          // a newer song asked meanwhile
                colors = pal
                done(img)
            }
        }
    }

    static func clear() { token += 1; colors = nil }

    // Spotify gives a link to the cover on its servers.
    private static func spotify() -> CGImage? {
        let url = osascript("tell application \"Spotify\" to return artwork url of current track")
        guard url.hasPrefix("https://"), let u = URL(string: url), let d = try? Data(contentsOf: u) else { return nil }
        return image(d)
    }

    // The Music app gives the image's bytes, printed as «data JPEG…» / «data PNGf…» (hex).
    private static func music() -> CGImage? {
        let out = osascript("tell application \"Music\" to return data of artwork 1 of current track")
        guard let start = out.range(of: "«data ")?.upperBound, let end = out.range(of: "»", range: start..<out.endIndex)?.lowerBound else { return nil }
        let body = out[start..<end].dropFirst(4)
        var bytes = [UInt8](); bytes.reserveCapacity(body.count / 2)
        var it = body.makeIterator()
        while let a = it.next(), let b = it.next() {
            guard let v = UInt8(String([a, b]), radix: 16) else { return nil }
            bytes.append(v)
        }
        return image(Data(bytes))
    }

    private static func image(_ d: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(d as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func osascript(_ script: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Its two most striking colors: the image shrunk to 32×32, pixels grouped by hue and weighted by how vivid they
    /// are; the strongest group, then the strongest one with a clearly different hue (or a lighter version of the
    /// first). Both made bright enough to be light in the water.
    static func palette(_ img: CGImage) -> (SIMD3<Float>, SIMD3<Float>)? {
        let n = 32
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: n, height: n))
        var sum = [SIMD3<Float>](repeating: .zero, count: 12), weight = [Float](repeating: 0, count: 12)
        var grey = SIMD3<Float>.zero, greyW: Float = 0
        for i in 0..<(n * n) {
            let c = SIMD3(Float(px[i * 4]), Float(px[i * 4 + 1]), Float(px[i * 4 + 2])) / 255
            let mx = max(c.x, max(c.y, c.z)), mn = min(c.x, min(c.y, c.z))
            let s = mx > 0 ? (mx - mn) / mx : 0
            if s < 0.2 || mx < 0.15 { grey += c; greyW += 1; continue }
            var h: Float
            if mx == c.x { h = (c.y - c.z) / (mx - mn) } else if mx == c.y { h = 2 + (c.z - c.x) / (mx - mn) } else { h = 4 + (c.x - c.y) / (mx - mn) }
            h = (h / 6).truncatingRemainder(dividingBy: 1); if h < 0 { h += 1 }
            let b = min(11, Int(h * 12)), w = s * mx * s + 0.02
            sum[b] += c * w; weight[b] += w
        }
        let order = (0..<12).sorted { weight[$0] > weight[$1] }
        func bright(_ c: SIMD3<Float>) -> SIMD3<Float> {
            let m = max(c.x, max(c.y, c.z), 0.001)
            return simd_clamp(c / m * 0.95, SIMD3(repeating: 0.05), SIMD3(repeating: 1))
        }
        guard let first = order.first, weight[first] > 0.5 else {
            // a black-and-white cover: a soft, cool white
            return greyW > 0 ? ([0.85, 0.9, 1.0], [0.7, 0.75, 0.85]) : nil
        }
        let a = bright(sum[first] / weight[first])
        let far = order.dropFirst().first { j in weight[j] > weight[first] * 0.12 && min(abs(j - first), 12 - abs(j - first)) >= 2 }
        let b = far.map { bright(sum[$0] / weight[$0]) } ?? simd_mix(a, SIMD3(repeating: 1), SIMD3(repeating: 0.45))
        return (a, b)
    }
}
