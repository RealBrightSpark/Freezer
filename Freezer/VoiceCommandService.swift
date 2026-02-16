import Foundation
import AVFoundation
import Speech
import Combine

@MainActor
final class VoiceCommandService: ObservableObject {
    @Published private(set) var isListening = false
    @Published var transcript = ""
    @Published var finalTranscript: String?
    @Published var statusMessage = "Tap Voice Remove to speak."
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    private let synthesizer = AVSpeechSynthesizer()

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func toggleListening() {
        if isListening {
            stopListening(submitTranscript: true)
        } else {
            Task {
                await startListening()
            }
        }
    }

    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        synthesizer.speak(utterance)
    }

    private func startListening() async {
        errorMessage = nil
        transcript = ""
        finalTranscript = nil

        guard speechRecognizer != nil else {
            errorMessage = "Speech recognition is unavailable on this device."
            statusMessage = "Speech unavailable."
            return
        }

        let speechGranted = await requestSpeechPermission()
        let micGranted = await requestMicrophonePermission()

        guard speechGranted, micGranted else {
            errorMessage = "Please allow microphone and speech recognition in Settings."
            statusMessage = "Permission required."
            return
        }

        do {
            try beginAudioSession()
            isListening = true
            statusMessage = "Listening..."
        } catch {
            errorMessage = "Could not start voice capture."
            statusMessage = "Voice capture failed."
            stopListening(submitTranscript: false)
        }
    }

    private func beginAudioSession() throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.stopListening(submitTranscript: true)
                    }
                }
            }

            if error != nil {
                Task { @MainActor in
                    if self.isListening {
                        self.errorMessage = "Speech recognition stopped unexpectedly."
                        self.stopListening(submitTranscript: false)
                    }
                }
            }
        }
    }

    private func stopListening(submitTranscript: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if submitTranscript {
            let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                statusMessage = "No speech detected."
            } else {
                finalTranscript = cleaned
                statusMessage = "Heard: \(cleaned)"
            }
        } else if errorMessage == nil {
            statusMessage = "Voice capture stopped."
        }
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}

struct VoiceRemoveCommand {
    let itemTerm: String
    let drawerNumber: Int?

    static func parse(from raw: String) -> VoiceRemoveCommand? {
        let removeKeywords = ["remove", "removed", "delete", "deleted", "took", "taken", "used"]
        let normalized = raw
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)

        guard removeKeywords.contains(where: { normalized.contains($0) }) else {
            return nil
        }

        var working = normalized
        var parsedDrawerNumber: Int?

        if let drawerMatch = working.range(of: "drawer\\s*([0-9]+)", options: .regularExpression) {
            let matchText = String(working[drawerMatch])
            if let numberText = matchText.components(separatedBy: CharacterSet.decimalDigits.inverted).joined().split(separator: " ").first,
               let drawer = Int(numberText) {
                parsedDrawerNumber = drawer
            } else {
                let digits = matchText.filter(\.isNumber)
                parsedDrawerNumber = Int(digits)
            }
            working.replaceSubrange(drawerMatch, with: " ")
        }

        let commandPhrases = [
            "i have removed", "i removed", "remove", "removed",
            "i have deleted", "i deleted", "delete", "deleted",
            "i took", "i have taken", "taken", "used"
        ]
        for phrase in commandPhrases {
            working = working.replacingOccurrences(of: phrase, with: " ")
        }

        let fillerWords = ["i", "have", "from", "the", "a", "an", "my", "freezer", "please", "item"]
        for word in fillerWords {
            working = working.replacingOccurrences(of: "\\b\(word)\\b", with: " ", options: .regularExpression)
        }

        let itemTerm = working
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !itemTerm.isEmpty else { return nil }
        return VoiceRemoveCommand(itemTerm: itemTerm, drawerNumber: parsedDrawerNumber)
    }
}
