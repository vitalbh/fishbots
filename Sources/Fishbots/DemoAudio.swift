import AVFoundation

/// Recording a demo (scripts/demo): writes the app's own sound to a file, with the Mac's voice mixed in, and notes
/// when it began (host clock, in <file>.json) so the video recorded beside it can be lined up to the frame.
enum DemoAudio {
    nonisolated(unsafe) private static var file: AVAudioFile?

    static func start(_ engine: AVAudioEngine, to url: URL) {
        stop(engine)
        let mixer = engine.mainMixerNode
        let fmt = mixer.outputFormat(forBus: 0)
        guard let f = try? AVAudioFile(forWriting: url, settings: fmt.settings, commonFormat: .pcmFormatFloat32, interleaved: false) else { return }
        file = f
        var first = true
        mixer.installTap(onBus: 0, bufferSize: 2048, format: fmt) { buf, when in
            if first {
                first = false
                let start = AVAudioTime.seconds(forHostTime: when.hostTime)
                try? Data("{\"start\":\(start)}".utf8).write(to: url.appendingPathExtension("json"))
            }
            try? file?.write(from: buf)
        }
        Speaker.shared.engine = engine
    }

    static func stop(_ engine: AVAudioEngine) {
        guard file != nil else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        file = nil
        Speaker.shared.engine = nil
    }
}
