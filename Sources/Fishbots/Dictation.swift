import AVFoundation
import Speech

/// Talk to the little fish: the Mac's own transcription (pt-BR, on-device when available).
/// An audio engine separate from the synthesizer, just for the microphone.
final class Dictation {
    static let shared = Dictation()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// In the interface language.
    private var recognizer: SFSpeechRecognizer? { SFSpeechRecognizer(locale: Locale(identifier: L10n.speechLanguage)) }
    private(set) var listening = false

    /// Starts listening. `partial` receives the text while you speak; `onError`, if something gets in the way.
    /// Called when it stops listening (you clicked, or it stopped on its own after a silence).
    private var onStop: (() -> Void)?

    func begin(partial: @escaping (String) -> Void, onError: @escaping (String) -> Void, end: (() -> Void)? = nil) {
        onStop = end
        guard !listening else { return }
        SFSpeechRecognizer.requestAuthorization { st in
            DispatchQueue.main.async {
                guard st == .authorized else { onError(tr("sem permissão de reconhecimento de fala (Ajustes → Privacidade)")); return }
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    DispatchQueue.main.async {
                        guard ok else { onError(tr("sem permissão do microfone (Ajustes → Privacidade)")); return }
                        self.start(partial: partial, onError: onError)
                    }
                }
            }
        }
    }

    private func start(partial: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        guard let r = recognizer, r.isAvailable else { onError(tr("reconhecimento de fala indisponível")); return }
        let p = SFSpeechAudioBufferRecognitionRequest()
        p.shouldReportPartialResults = true
        if r.supportsOnDeviceRecognition { p.requiresOnDeviceRecognition = true }   // stays on the Mac
        request = p
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak p] buf, _ in p?.append(buf) }
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            onError(tr("não consegui abrir o microfone: %@", error.localizedDescription))
            return
        }
        listening = true
        // after a pause, the recognizer closes the segment and starts over from scratch: we keep the segments and join them
        var stored = ""
        var last = ""
        func join(_ a: String, _ b: String) -> String { a.isEmpty ? b : b.isEmpty ? a : a + " " + b }
        task = r.recognitionTask(with: p) { res, err in
            if let res {
                let t = res.bestTranscription.formattedString
                DispatchQueue.main.async {
                    if res.isFinal {
                        stored = join(stored, t); last = ""
                        partial(stored)
                    } else {
                        if Self.newChunk(before: last, now: t) { stored = join(stored, last) }
                        last = t
                        partial(join(stored, t))
                    }
                }
            }
            if err != nil || res?.isFinal == true { DispatchQueue.main.async { self.stop() } }
        }
    }

    /// Did the recognizer start over (the new text doesn't continue the previous one and is much shorter)?
    static func newChunk(before: String, now: String) -> Bool {
        guard !before.isEmpty else { return false }
        let a = before.lowercased(), b = now.lowercased()
        let start = String(a.prefix(min(10, a.count)))
        return !b.hasPrefix(start) && b.count < max(8, a.count * 2 / 3)
    }

    func stop() {
        guard listening else { return }
        listening = false
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        request?.endAudio()
        request = nil
        task?.finish()
        task = nil
        let f = onStop
        onStop = nil
        f?()
    }
}
