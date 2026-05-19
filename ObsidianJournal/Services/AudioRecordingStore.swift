import AVFoundation
import Foundation
import os

enum AudioRecordingStoreError: Error, LocalizedError {
    case noRecordings
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .noRecordings:
            return "No audio recordings are available to share."
        case .exportFailed:
            return "Could not create the combined audio file."
        }
    }
}

final class AudioRecordingStore {
    static let shared = AudioRecordingStore()

    private let recordingsFolderName = "Recordings"
    private let exportFolderName = "RecordingExports"
    private let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

    private init() {}

    func makeRecordingURL() throws -> URL {
        let directory = try recordingsDirectory()
        let fileName = "recording-\(Self.fileNameFormatter.string(from: Date()))-\(UUID().uuidString).m4a"
        return directory.appendingPathComponent(fileName)
    }

    func makeRecordingMetadata(
        for fileURL: URL,
        noteDate: Date,
        transcriptText: String
    ) -> DraftAudioRecording {
        let duration = (try? AVAudioPlayer(contentsOf: fileURL).duration) ?? 0
        let byteSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        return DraftAudioRecording(
            createdAt: Date(),
            noteDate: noteDate,
            relativePath: relativePath(for: fileURL),
            duration: duration.isFinite ? duration : 0,
            byteSize: byteSize,
            transcriptText: transcriptText,
            status: .active
        )
    }

    func fileURL(for recording: DraftAudioRecording) -> URL? {
        guard let directory = try? recordingsDirectory() else { return nil }
        return directory.appendingPathComponent(recording.relativePath)
    }

    func deleteRecordings(_ recordings: [DraftAudioRecording]) {
        for recording in recordings {
            guard let url = fileURL(for: recording),
                  FileManager.default.fileExists(atPath: url.path) else {
                continue
            }

            do {
                try FileManager.default.removeItem(at: url)
                Logger.audio.info("Deleted recording: \(url.lastPathComponent)")
            } catch {
                Logger.audio.error("Failed to delete recording \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    func removeExpiredRecordings(from drafts: inout [Draft]) -> Bool {
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        var didChange = false

        for index in drafts.indices {
            let expired = drafts[index].recordings.filter { $0.createdAt < cutoff }
            guard !expired.isEmpty else { continue }

            deleteRecordings(expired)
            drafts[index].recordings.removeAll { $0.createdAt < cutoff }
            didChange = true
        }

        return didChange
    }

    func exportCombinedAudio(for recordings: [DraftAudioRecording]) async throws -> URL {
        let sourceURLs = recordings
            .sorted { $0.createdAt < $1.createdAt }
            .compactMap(fileURL(for:))
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        guard !sourceURLs.isEmpty else {
            throw AudioRecordingStoreError.noRecordings
        }

        let exportURL = try makeExportURL()

        if sourceURLs.count == 1 {
            try FileManager.default.copyItem(at: sourceURLs[0], to: exportURL)
            return exportURL
        }

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioRecordingStoreError.exportFailed
        }

        var cursor = CMTime.zero
        for url in sourceURLs {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let duration = try await asset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: duration)
            try compositionTrack.insertTimeRange(range, of: track, at: cursor)
            cursor = CMTimeAdd(cursor, duration)
        }

        guard CMTimeCompare(cursor, .zero) > 0,
              let session = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetAppleM4A
              ) else {
            throw AudioRecordingStoreError.exportFailed
        }

        session.outputURL = exportURL
        session.outputFileType = .m4a
        session.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { continuation in
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        guard session.status == .completed else {
            if let error = session.error {
                Logger.audio.error("Audio export failed: \(error.localizedDescription)")
            }
            throw AudioRecordingStoreError.exportFailed
        }

        return exportURL
    }

    private func recordingsDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent(recordingsFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func exportsDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(exportFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeExportURL() throws -> URL {
        let directory = try exportsDirectory()
        let url = directory.appendingPathComponent("journal-audio-\(Self.fileNameFormatter.string(from: Date())).m4a")

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        return url
    }

    private func relativePath(for url: URL) -> String {
        url.lastPathComponent
    }

    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
