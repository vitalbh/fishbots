import AVFoundation

/// The aquarium reading aloud (the Mac's voice): the last reply via the card's 🔊, and questions, if you turn it on.
/// Uses the best installed pt-BR voice (premium > enhanced > default) and ducks the music while speaking.
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()
    private let synthesizer = AVSpeechSynthesizer()
    /// Ducks and restores the music (the app wires this to the synthesizer's mixer).
    var muffle: ((Bool) -> Void)?
    var speaking: Bool { synthesizer.isSpeaking || intoEngine }
    /// Recording a demo: the voice is mixed into the app's own sound (DemoAudio) instead of played by the system.
    var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var intoEngine = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// The best installed voice in the interface language: premium or enhanced, if downloaded; otherwise the plain
    /// everyday voices (the others are novelty voices).
    private var voice: AVSpeechSynthesisVoice? {
        let lang = L10n.speechLanguage
        if let v = cached, v.language == lang { return v }
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == lang }
        let plain = lang == "pt-BR" ? ["Luciana", "Felipe"] : ["Samantha", "Alex", "Ava", "Allison"]
        cached = all.filter({ $0.quality != .default }).max(by: { $0.quality.rawValue < $1.quality.rawValue })
            ?? all.first { plain.contains($0.name) } ?? AVSpeechSynthesisVoice(language: lang)
        return cached
    }
    private var cached: AVSpeechSynthesisVoice?

    func speak(_ text: String) {
        stop()
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        muffle?(true)
        if let engine { speak(u, into: engine); return }
        synthesizer.speak(u)
    }

    private func speak(_ u: AVSpeechUtterance, into engine: AVAudioEngine) {
        intoEngine = true
        var converter: AVAudioConverter?
        synthesizer.write(u) { [weak self] buffer in
            guard let self, let pcm = buffer as? AVAudioPCMBuffer else { return }
            guard pcm.frameLength > 0 else {
                // the end: back to normal once the last bit has played
                self.player?.scheduleBuffer(AVAudioPCMBuffer(pcmFormat: self.player!.outputFormat(forBus: 0), frameCapacity: 1)!) {
                    DispatchQueue.main.async { self.intoEngine = false; self.muffle?(false) }
                }
                return
            }
            guard let fmt = AVAudioFormat(standardFormatWithSampleRate: pcm.format.sampleRate, channels: pcm.format.channelCount) else { return }
            if self.player == nil || self.player!.outputFormat(forBus: 0) != fmt {
                if let p = self.player { engine.detach(p) }
                let p = AVAudioPlayerNode()
                engine.attach(p)
                engine.connect(p, to: engine.mainMixerNode, format: fmt)
                p.play()
                self.player = p
            }
            var out = pcm
            if pcm.format != fmt {
                if converter == nil { converter = AVAudioConverter(from: pcm.format, to: fmt) }
                guard let c = converter, let o = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: pcm.frameLength) else { return }
                try? c.convert(to: o, from: pcm)
                out = o
            }
            self.player?.scheduleBuffer(out)
        }
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        player?.stop(); player?.play()
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { muffle?(false) }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { muffle?(false) }
}
