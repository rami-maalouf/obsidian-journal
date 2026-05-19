import Foundation

enum DraftStatus: String, Codable, Equatable {
    case draft
    case archived
}

enum DraftAudioRecordingStatus: String, Codable, Equatable {
    case active
    case submitted
}

struct DraftAudioRecording: Identifiable, Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var noteDate: Date
    var relativePath: String
    var duration: TimeInterval
    var byteSize: Int
    var transcriptText: String
    var status: DraftAudioRecordingStatus

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        noteDate: Date,
        relativePath: String,
        duration: TimeInterval,
        byteSize: Int,
        transcriptText: String = "",
        status: DraftAudioRecordingStatus = .active
    ) {
        self.id = id
        self.createdAt = createdAt
        self.noteDate = noteDate
        self.relativePath = relativePath
        self.duration = duration
        self.byteSize = byteSize
        self.transcriptText = transcriptText
        self.status = status
    }
}

struct Draft: Identifiable, Codable, Equatable {
    var id: UUID
    var content: String
    var createdAt: Date
    var modifiedAt: Date
    var status: DraftStatus // New property
    var recordings: [DraftAudioRecording]

    init(
        id: UUID = UUID(),
        content: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        status: DraftStatus = .draft,
        recordings: [DraftAudioRecording] = []
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.status = status
        self.recordings = recordings
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case content
        case createdAt
        case modifiedAt
        case status
        case recordings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        status = try container.decodeIfPresent(DraftStatus.self, forKey: .status) ?? .draft
        recordings = try container.decodeIfPresent([DraftAudioRecording].self, forKey: .recordings) ?? []
    }
}
