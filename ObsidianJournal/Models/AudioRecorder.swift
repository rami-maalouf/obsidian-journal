import Foundation
import AVFoundation
import os

class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var recordingURL: URL?
    @Published var audioLevel: Float = 0.0

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var lastDetectedAudioAt: Date?
    private let monitoringInterval: TimeInterval = 0.1
    private let smoothingFactor: Float = 0.2
    private let speechNoiseFloorMarginDB: Float = 4.0
    private let minimumSpeechThresholdDB: Float = -45.0
    private let maximumSpeechThresholdDB: Float = -8.0
    private var smoothedAveragePower: Float = -160.0
    private var noiseFloorDB: Float = -55.0
    private var lastMonitorLogAt: Date?

    private enum StopReason {
        case manual
        case silenceTimeout

        var logDescription: String {
            switch self {
            case .manual:
                return "manual"
            case .silenceTimeout:
                return "silence timeout"
            }
        }
    }

    override init() {
        super.init()
    }

    func startRecording() {
        Logger.audio.info("Initiating recording flow...")
        let recordingSession = AVAudioSession.sharedInstance()

        do {
            // Configure for background audio recording
            try recordingSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetoothHFP, .defaultToSpeaker]
            )
            try recordingSession.setActive(true, options: .notifyOthersOnDeactivation)

            let audioFilename = try AudioRecordingStore.shared.makeRecordingURL()
            Logger.audio.debug("Recording path: \(audioFilename.path)")

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32000,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            isRecording = true
            recordingURL = nil
            lastDetectedAudioAt = Date()
            smoothedAveragePower = -160.0
            noiseFloorDB = -55.0
            lastMonitorLogAt = nil

            startMonitoring()
            Logger.audio.notice("Recording started (AAC M4A 16kHz).")

        } catch {
            Logger.audio.error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        stopRecording(reason: .manual)
    }

    private func stopRecording(reason: StopReason) {
        guard isRecording else { return }

        Logger.audio.info("Stopping recording (\(reason.logDescription))...")
        audioRecorder?.stop()
        isRecording = false
        stopMonitoring()
        recordingURL = audioRecorder?.url
        lastDetectedAudioAt = nil

        if let url = recordingURL {
            do {
                let resources = try url.resourceValues(forKeys: [.fileSizeKey])
                let fileSize = resources.fileSize ?? 0
                Logger.audio.notice("Recording stopped. File saved. Size: \(fileSize) bytes")
            } catch {
                Logger.audio.error("Could not determine file size.")
            }
        }
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: monitoringInterval, repeats: true) { [weak self] _ in
            guard let self, let audioRecorder = self.audioRecorder else { return }

            audioRecorder.updateMeters()

            let averagePower = audioRecorder.averagePower(forChannel: 0)
            let smoothedAveragePower = self.smoothedAveragePower == -160.0
                ? averagePower
                : (self.smoothingFactor * averagePower) + ((1 - self.smoothingFactor) * self.smoothedAveragePower)

            self.smoothedAveragePower = smoothedAveragePower
            self.audioLevel = smoothedAveragePower
            self.handleSilenceDetection(averagePower: smoothedAveragePower)
        }

        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        audioLevel = 0.0
        lastDetectedAudioAt = nil
        smoothedAveragePower = -160.0
        noiseFloorDB = -55.0
        lastMonitorLogAt = nil
    }

    private func handleSilenceDetection(averagePower: Float) {
        let silenceTimeout = TranscriptionSettings.shared.silenceAutoStopInterval

        guard silenceTimeout > 0 else { return }

        let speechThreshold = min(
            max(noiseFloorDB + speechNoiseFloorMarginDB, minimumSpeechThresholdDB),
            maximumSpeechThresholdDB
        )

        if averagePower >= speechThreshold {
            lastDetectedAudioAt = Date()
        } else {
            updateNoiseFloor(with: averagePower)
        }

        guard let lastDetectedAudioAt else {
            self.lastDetectedAudioAt = Date()
            return
        }

        let silenceElapsed = Date().timeIntervalSince(lastDetectedAudioAt)
        maybeLogMonitoringState(
            averagePower: averagePower,
            speechThreshold: speechThreshold,
            silenceElapsed: silenceElapsed
        )

        if silenceElapsed >= silenceTimeout {
            Logger.audio.notice(
                "Auto-stopping recording after \(Int(silenceTimeout)) seconds of silence."
            )
            stopRecording(reason: .silenceTimeout)
        }
    }

    private func updateNoiseFloor(with averagePower: Float) {
        if averagePower < noiseFloorDB {
            noiseFloorDB = averagePower
            return
        }

        noiseFloorDB = min(noiseFloorDB + 0.05, averagePower)
    }

    private func maybeLogMonitoringState(
        averagePower: Float,
        speechThreshold: Float,
        silenceElapsed: TimeInterval
    ) {
        let now = Date()

        guard lastMonitorLogAt == nil || now.timeIntervalSince(lastMonitorLogAt!) >= 5 else {
            return
        }

        lastMonitorLogAt = now
        Logger.audio.debug(
            """
            Silence monitor avg=\(averagePower)dB noiseFloor=\(self.noiseFloorDB)dB threshold=\(speechThreshold)dB elapsed=\(Int(silenceElapsed))s
            """
        )
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Logger.audio.error("Audio Recorder finish flag is false.")
            recordingURL = nil
        } else {
            Logger.audio.info("Audio Recorder finished successfully.")
        }
    }
}
