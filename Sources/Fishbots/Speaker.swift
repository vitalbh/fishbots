import AVFoundation

/// The aquarium reading aloud (the Mac's voice): the last reply via the card's 🔊, and questions, if you turn it on.
/// Uses the best installed pt-BR voice (premium > enhanced > default) and ducks the music while speaking.
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()
    private let synthesizer = AVSpeechSynthesizer()
    /// Ducks and restores the music (the app wires this to the synthesizer's mixer).
    var muffle: ((Bool) -> Void)?
    var speaking: Bool { synthesizer.isSpeaking }

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
        synthesizer.speak(u)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { muffle?(false) }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { muffle?(false) }
}
