import Foundation
import os

/// Available transcription models - both local WhisperKit and cloud OpenAI
enum TranscriptionModel: String, CaseIterable, Codable, Identifiable {
    // Local models (WhisperKit) - ordered by size
    case tiny = "openai_whisper-tiny.en"
    case base = "openai_whisper-base.en"
    case small = "openai_whisper-small.en"
    case medium = "openai_whisper-medium"
    case largeV3 = "distil-whisper_distil-large-v3_turbo"

    // Cloud option
    case cloudOpenAI = "cloud_openai_whisper"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: return "Tiny (English)"
        case .base: return "Base (English)"
        case .small: return "Small (English)"
        case .medium: return "Medium (English)"
        case .largeV3: return "Large v3 (Best)"
        case .cloudOpenAI: return "Cloud (OpenAI)"
        }
    }

    var isCloud: Bool {
        self == .cloudOpenAI
    }

    var sizeDescription: String {
        switch self {
        case .tiny: return "~39 MB"
        case .base: return "~74 MB"
        case .small: return "~244 MB"
        case .medium: return "~769 MB"
        case .largeV3: return "~626 MB"
        case .cloudOpenAI: return "Uses API"
        }
    }

    var accuracyDescription: String {
        switch self {
        case .tiny: return "Basic"
        case .base: return "Good"
        case .small: return "Better"
        case .medium: return "High"
        case .largeV3: return "Excellent"
        case .cloudOpenAI: return "Excellent"
        }
    }
}

/// Manages transcription preferences with persistence
class TranscriptionSettings: ObservableObject {
    static let shared = TranscriptionSettings()

    private let defaults = UserDefaults(
        suiteName: "group.studio.orbitlabs.ignite"
    )
    private static let modelKey = "selectedTranscriptionModel"
    private static let silenceAutoStopIntervalKey = "silenceAutoStopInterval"
    static let defaultSilenceAutoStopInterval: TimeInterval = 120

    @Published var selectedModel: TranscriptionModel {
        didSet {
            saveModel()
        }
    }

    @Published var silenceAutoStopInterval: TimeInterval {
        didSet {
            saveSilenceAutoStopInterval()
        }
    }

    private init() {
        let savedSilenceAutoStopInterval = defaults?.object(
            forKey: Self.silenceAutoStopIntervalKey
        ) as? Double

        // Restore saved model or default to cloud
        if let savedRawValue = defaults?.string(forKey: Self.modelKey),
            let model = TranscriptionModel(rawValue: savedRawValue)
        {
            self.selectedModel = model
            Logger.transcription.info(
                "Restored transcription model: \(model.displayName)"
            )
        } else {
            self.selectedModel = .cloudOpenAI
            Logger.transcription.info(
                "Using default transcription model: Cloud (OpenAI)"
            )
        }

        self.silenceAutoStopInterval =
            savedSilenceAutoStopInterval ?? Self.defaultSilenceAutoStopInterval
        Logger.transcription.info(
            "Using silence auto-stop interval: \(Int(self.silenceAutoStopInterval)) seconds"
        )
    }

    private func saveModel() {
        defaults?.set(selectedModel.rawValue, forKey: Self.modelKey)
        Logger.transcription.info(
            "Saved transcription model: \(self.selectedModel.displayName)"
        )
    }

    private func saveSilenceAutoStopInterval() {
        defaults?.set(
            silenceAutoStopInterval,
            forKey: Self.silenceAutoStopIntervalKey
        )
        Logger.transcription.info(
            "Saved silence auto-stop interval: \(Int(self.silenceAutoStopInterval)) seconds"
        )
    }
}
