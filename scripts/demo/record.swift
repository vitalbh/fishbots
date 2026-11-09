// Records the Fishbots windows (the aquarium and its cards), for demo videos. The sound comes from the app itself
// (/test/do?audio=start:<file>), lined up by the host clock: both note when they began in <file>.json.
//   swiftc -O scripts/demo/record.swift -o .build/demo-record
//   .build/demo-record <pid> <seconds> <out.mov> [display]
// Only that app is drawn (other apps are left out). The region is its main window's,
// or the whole display with "display" (the widget in its corner). Needs Screen Recording permission.
import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

let args = CommandLine.arguments
guard args.count >= 4, let pid = pid_t(args[1]), let seconds = Double(args[2]) else {
    FileHandle.standardError.write(Data("usage: record <pid> <seconds> <out.mov> [display]\n".utf8)); exit(2)
}
let out = URL(fileURLWithPath: args[3])
let wholeDisplay = args.count > 4 && args[4] == "display"
try? FileManager.default.removeItem(at: out)

final class Recorder: NSObject, SCStreamOutput {
    let writer: AVAssetWriter
    let video: AVAssetWriterInput
    let startFile: URL
    var started = false

    init(out: URL, width: Int, height: Int) throws {
        writer = try AVAssetWriter(outputURL: out, fileType: .mov)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 40_000_000, AVVideoExpectedSourceFrameRateKey: 60],
        ])
        video.expectsMediaDataInRealTime = true
        writer.add(video)
        startFile = out.appendingPathExtension("json")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sb.isValid else { return }
        if type == .screen {
            // only complete frames (idle ones repeat the last and carry no image)
            guard let att = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
                  let raw = att[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
            if !started {
                writer.startWriting()
                writer.startSession(atSourceTime: sb.presentationTimeStamp)
                started = true
                try? Data("{\"start\":\(sb.presentationTimeStamp.seconds)}".utf8).write(to: startFile)
            }
            if video.isReadyForMoreMediaData { video.append(sb) }
        }
    }
}

/// The app's main window on screen (the biggest), in display points.
func mainWindow(of pid: pid_t) -> CGRect? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
        .compactMap { w -> CGRect? in (w[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } }
        .max { $0.width * $0.height < $1.width * $1.height }
}

let done = DispatchSemaphore(value: 0)
Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let app = content.applications.first(where: { $0.processID == pid }) else { throw NSError(domain: "record", code: 1, userInfo: [NSLocalizedDescriptionKey: "no app with pid \(pid)"]) }
        guard let win = mainWindow(of: pid) else { throw NSError(domain: "record", code: 2, userInfo: [NSLocalizedDescriptionKey: "no window"]) }
        let display = content.displays.first { $0.frame.contains(CGPoint(x: win.midX, y: win.midY)) } ?? content.displays[0]
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let scale = Int(filter.pointPixelScale)
        let region = wholeDisplay ? CGRect(origin: .zero, size: display.frame.size)
                                  : win.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = region
        cfg.width = Int(region.width) * scale / 2 * 2
        cfg.height = Int(region.height) * scale / 2 * 2
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        cfg.queueDepth = 8
        cfg.showsCursor = false
        cfg.backgroundColor = .black
        let rec = try Recorder(out: out, width: cfg.width, height: cfg.height)
        let stream = SCStream(filter: filter, configuration: cfg, delegate: nil)
        let q = DispatchQueue(label: "record")
        try stream.addStreamOutput(rec, type: .screen, sampleHandlerQueue: q)
        try await stream.startCapture()
        try await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
        try await stream.stopCapture()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            q.async {
                rec.video.markAsFinished()
                rec.writer.finishWriting { c.resume() }
            }
        }
        if rec.writer.status != .completed { throw rec.writer.error ?? NSError(domain: "record", code: 3) }
        print("\(out.path) \(cfg.width)x\(cfg.height)")
    } catch {
        FileHandle.standardError.write(Data("record: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    done.signal()
}
done.wait()
