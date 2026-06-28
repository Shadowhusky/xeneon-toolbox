import Foundation
import Speech
import AVFoundation

/// On-device push-to-talk dictation. Transcribes the mic locally (no cloud) and
/// hands the final text to a callback — used to speak to the assistant. macOS has
/// no AVAudioSession, so this just taps the input node directly.
@MainActor
final class VoiceInput: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var transcript = ""
    /// nil = not yet asked; true/false after authorization.
    @Published private(set) var authorized: Bool?

    var onFinal: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Whether voice is usable at all on this machine.
    var supported: Bool { recognizer != nil }

    func toggle() { listening ? stop() : start() }

    func start() {
        guard !listening, let recognizer, recognizer.isAvailable else { return }
        ensureAuthorized { [weak self] ok in
            guard let self, ok else { return }
            self.beginListening()
        }
    }

    func stop() {
        request?.endAudio()
        finish()
    }

    private func ensureAuthorized(_ done: @escaping (Bool) -> Void) {
        let speech = SFSpeechRecognizer.authorizationStatus()
        func afterSpeech(_ granted: Bool) {
            guard granted else { authorized = false; done(false); return }
            AVCaptureDevice.requestAccess(for: .audio) { mic in
                DispatchQueue.main.async { self.authorized = mic; done(mic) }
            }
        }
        switch speech {
        case .authorized: afterSpeech(true)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { s in
                DispatchQueue.main.async { afterSpeech(s == .authorized) }
            }
        default: authorized = false; done(false)
        }
    }

    private func beginListening() {
        guard let recognizer else { return }
        transcript = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { cleanup(); return }
        listening = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result { self.transcript = result.bestTranscription.formattedString }
                if (result?.isFinal ?? false) || error != nil { self.finish() }
            }
        }
    }

    private func finish() {
        guard listening else { return }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanup()
        if !text.isEmpty { onFinal?(text) }
    }

    private func cleanup() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        task?.cancel(); task = nil
        request = nil
        listening = false
    }
}
