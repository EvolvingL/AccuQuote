import SwiftUI
import Speech
import AVFoundation

// MARK: - Voice Recorder

/// Captures a live mic transcript for the job-description field. Runs on the
/// main actor because `@Published` updates drive SwiftUI directly — the speech
/// framework's recognition callbacks are hopped onto @MainActor internally
/// rather than trusting their delivery thread.
@MainActor
final class VoiceRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var transcript  = ""
    @Published var amplitude: [CGFloat] = Array(repeating: 0.12, count: 40)
    @Published var permissionDenied = false

    private var audioEngine      = AVAudioEngine()
    private var tapInstalled     = false   // guards removeTap — prevents crash when stop() called before beginRecording()
    private var recognitionTask:   SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
    private var amplitudeTimer: Timer?

    func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard status == .authorized else {
                    self.permissionDenied = true
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else { self.permissionDenied = true; return }
                        self.beginRecording()
                    }
                }
            }
        }
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.transcript = result.bestTranscription.formattedString
            }
            if error != nil || (result?.isFinal == true) {
                self.stop()
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            let bufPtr = UnsafeBufferPointer(start: channelData, count: frameCount)
            let rms = sqrt(bufPtr.reduce(Float(0)) { $0 + $1 * $1 } / Float(frameCount))
            let db = CGFloat(max(0.05, min(1.0, Double(rms) * 12)))
            DispatchQueue.main.async {
                self?.pushAmplitude(db)
            }
        }
        tapInstalled = true   // mark so stop() only calls removeTap when a tap exists

        try? audioEngine.start()
        isRecording = true

        // Animate idle waveform when no audio
        amplitudeTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self, self.isRecording else { return }
            Task { @MainActor in
                if self.amplitude.allSatisfy({ $0 < 0.15 }) {
                    self.pushAmplitude(CGFloat.random(in: 0.05...0.18))
                }
            }
        }
    }

    private func pushAmplitude(_ v: CGFloat) {
        amplitude.removeFirst()
        amplitude.append(v)
    }

    func stop() {
        amplitudeTimer?.invalidate(); amplitudeTimer = nil
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        // Fade amplitude back to rest
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.4)) {
                amplitude = Array(repeating: 0.12, count: 40)
            }
        }
    }
}

// MARK: - Voice Input Card

struct VoiceInputCard: View {
    @ObservedObject var recorder: VoiceRecorder
    @Binding var transcript: String
    @State private var pulseRing = false

    var body: some View {
        VStack(spacing: 20) {

            // Waveform
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<recorder.amplitude.count, id: \.self) { i in
                    Capsule()
                        .fill(recorder.isRecording ? AQ.blue : AQ.rule)
                        .frame(width: 3, height: max(4, recorder.amplitude[i] * 48))
                        .animation(.easeOut(duration: 0.08), value: recorder.amplitude[i])
                }
            }
            .frame(height: 56)
            .padding(.horizontal, 4)

            // Transcript or prompt
            if transcript.isEmpty {
                Text(recorder.isRecording
                     ? "Listening…"
                     : "Tap the mic and describe the job")
                    .font(.system(size: 14))
                    .foregroundColor(AQ.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(transcript)
                    .font(.system(size: 15))
                    .foregroundColor(AQ.ink)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            // Mic button
            ZStack {
                // Pulse ring — only while recording
                if recorder.isRecording {
                    Circle()
                        .stroke(AQ.blue.opacity(0.2), lineWidth: 2)
                        .frame(width: 84, height: 84)
                        .scaleEffect(pulseRing ? 1.22 : 1.0)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                   value: pulseRing)
                        .onAppear { pulseRing = true }
                        .onDisappear { pulseRing = false }
                }

                Button { recorder.toggle() } label: {
                    ZStack {
                        Circle()
                            .fill(recorder.isRecording ? AQ.blue : AQ.fill)
                            .frame(width: 64, height: 64)
                            .shadow(color: recorder.isRecording ? AQ.blue.opacity(0.3) : .clear,
                                    radius: 12, x: 0, y: 4)
                            .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic")
                            .font(.system(size: recorder.isRecording ? 18 : 22, weight: .medium))
                            .foregroundColor(recorder.isRecording ? .white : AQ.ink)
                            .animation(.easeInOut(duration: 0.15), value: recorder.isRecording)
                    }
                }
            }
            .frame(height: 84)

            if recorder.permissionDenied {
                Text("Microphone access denied. Enable in Settings → AccuQuote Scan → Microphone.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.85, green: 0.35, blue: 0.2))
                    .multilineTextAlignment(.center)
            }

            if !transcript.isEmpty && !recorder.isRecording {
                Button {
                    transcript = ""
                    recorder.transcript = ""
                } label: {
                    Text("Clear and re-record")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AQ.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(recorder.isRecording ? AQ.blue.opacity(0.4) : AQ.rule, lineWidth: 1)
                .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
        )
    }
}

// MARK: - Quote Line Item model

