import Foundation

// MARK: - Rami Daily Note Response
//
// Deterministic JSON shape for populating:
// My Calendar/My Daily Notes/YYYY-MM-DD.md
//
// Every template field maps to exactly one JSON key.
// Use null when the transcript does not mention that field.

public struct RamiDailyNoteResponse: Codable, Equatable {
    public let metadata: RamiDailyNoteMetadata
    public let reminders: RamiDailyNoteReminders
    public let morningMindset: RamiDailyNoteMorningMindset
    public let reflection: RamiDailyNoteReflection
    public let processingNotes: String?

    enum CodingKeys: String, CodingKey {
        case metadata
        case reminders
        case morningMindset = "morning_mindset"
        case reflection
        case processingNotes = "processing_notes"
    }
}

// MARK: - Frontmatter (metadata)

public struct RamiDailyNoteMetadata: Codable, Equatable {
    /// Dreams: free-text dream journal from the night
    public let dreams: String?

    /// Summary: one-line summary of the day
    public let summary: String?

    /// true when the user marks this as a storyworthy day (adds ref/storyworthy tag)
    public let storyworthy: Bool?

    /// true when the user marks accomplishments for the day (adds ref/accomplishment tag)
    public let accomplishment: Bool?

    /// Ratings 1-10. null if not stated or implied in the transcript.
    public let intention: Int?
    public let discipline: Int?
    public let focus: Int?
    public let courage: Int?
    public let purpose: Int?
    public let energy: Int?
    public let communication: Int?
    public let uniqueness: Int?
    public let rating: Int?
}

// MARK: - Reminders

public struct RamiDailyNoteReminders: Codable, Equatable {
    /// Today's Big 3 - exactly 3 slots, null per slot if not mentioned
    public let big3: [String?]

    /// 3 things grateful for - exactly 3 slots
    public let gratefulFor: [String?]

    /// true if user says they planned their top 5 habits; null if not mentioned
    public let habitsPlanned: Bool?

    enum CodingKeys: String, CodingKey {
        case big3 = "big_3"
        case gratefulFor = "grateful_for"
        case habitsPlanned = "habits_planned"
    }
}

// MARK: - Morning Mindset

public struct RamiDailyNoteMorningMindset: Codable, Equatable {
    public let excitedFor: String?
    public let oneWordAndBecause: String?
    public let someoneNeedsMe: String?
    public let potentialObstacle: String?
    public let surpriseSomeone: String?
    public let excellenceAction: String?
    public let boldAction: String?
    public let coachWouldSay: String?
    public let wouldDoIfNoFail: String?
    public let goal: String?
    public let bottleneck: String?
    public let successCriteria: String?

    enum CodingKeys: String, CodingKey {
        case excitedFor = "excited_for"
        case oneWordAndBecause = "one_word_and_because"
        case someoneNeedsMe = "someone_needs_me"
        case potentialObstacle = "potential_obstacle"
        case surpriseSomeone = "surprise_someone"
        case excellenceAction = "excellence_action"
        case boldAction = "bold_action"
        case coachWouldSay = "coach_would_say"
        case wouldDoIfNoFail = "would_do_if_no_fail"
        case goal
        case bottleneck
        case successCriteria = "success_criteria"
    }
}

// MARK: - Reflection

public struct RamiDailyNoteReflection: Codable, Equatable {
    /// ## Reflection > ### Accomplishments
    public let accomplishments: String?

    /// #### what did I control?
    public let whatIControlled: String?

    /// ### Obstacles
    public let obstacles: String?

    /// #### was there a situation where I went against my moral compass?
    public let moralCompass: String?

    /// ### Improvements
    public let improvements: String?

    /// #### Communication (under Improvements)
    public let communication: RamiDailyNoteCommunicationReflection?

    enum CodingKeys: String, CodingKey {
        case accomplishments
        case whatIControlled = "what_i_controlled"
        case obstacles
        case moralCompass = "moral_compass"
        case improvements
        case communication
    }
}

public struct RamiDailyNoteCommunicationReflection: Codable, Equatable {
    public let wentWell: String?
    public let didntGoWell: String?

    enum CodingKeys: String, CodingKey {
        case wentWell = "went_well"
        case didntGoWell = "didnt_go_well"
    }
}

// MARK: - OpenAI JSON Schema

public enum RamiDailyNoteSchema {
    /// Obsidian tag added to frontmatter when storyworthy is true.
    public static let storyworthyTag = "ref/storyworthy"

    /// Obsidian tag added to frontmatter when accomplishment is true.
    public static let accomplishmentTag = "ref/accomplishment"

    /// Deterministic transcript check for storyworthy mentions.
    public static func detectsStoryworthy(in transcript: String) -> Bool {
        let pattern = #"(?i)(@storyworthy|@story[\s-]?worthy|story[\s-]?worthy\s+day|this\s+(is|was)\s+(a\s+)?story[\s-]?worthy)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(transcript.startIndex..., in: transcript)
        return regex.firstMatch(in: transcript, range: range) != nil
    }

    /// Deterministic transcript check for accomplishment mentions.
    public static func detectsAccomplishment(in transcript: String) -> Bool {
        let pattern = #"(?i)(@accomplishment|@accomplishments|accomplishment\s+day|this\s+(is|was)\s+(an?\s+)?accomplishment|today(?:'s)?\s+accomplishment)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(transcript.startIndex..., in: transcript)
        return regex.firstMatch(in: transcript, range: range) != nil
    }

    /// Resolves storyworthy from LLM output plus deterministic transcript scan.
    public static func shouldApplyStoryworthyTag(response: RamiDailyNoteResponse, transcript: String) -> Bool {
        if response.metadata.storyworthy == false { return false }
        if response.metadata.storyworthy == true { return true }
        return detectsStoryworthy(in: transcript)
    }

    /// Resolves accomplishment tag from LLM output plus deterministic transcript scan.
    public static func shouldApplyAccomplishmentTag(response: RamiDailyNoteResponse, transcript: String) -> Bool {
        if response.metadata.accomplishment == false { return false }
        if response.metadata.accomplishment == true { return true }
        return detectsAccomplishment(in: transcript)
    }

    /// Applies all ref/* tags warranted by the response and transcript.
    public static func applyRefTags(
        to note: String,
        response: RamiDailyNoteResponse,
        transcript: String
    ) -> String {
        var result = note
        result = applyStoryworthyTag(to: result, response: response, transcript: transcript)
        result = applyAccomplishmentTag(to: result, response: response, transcript: transcript)
        return result
    }

    /// Adds `ref/storyworthy` to YAML frontmatter tags when warranted.
    public static func applyStoryworthyTag(
        to note: String,
        response: RamiDailyNoteResponse,
        transcript: String
    ) -> String {
        applyTag(to: note, tag: storyworthyTag, shouldApply: shouldApplyStoryworthyTag(response: response, transcript: transcript))
    }

    /// Adds `ref/storyworthy` to YAML frontmatter tags when warranted.
    public static func applyStoryworthyTag(to note: String, storyworthy: Bool) -> String {
        applyTag(to: note, tag: storyworthyTag, shouldApply: storyworthy)
    }

    /// Adds `ref/accomplishment` to YAML frontmatter tags when warranted.
    public static func applyAccomplishmentTag(
        to note: String,
        response: RamiDailyNoteResponse,
        transcript: String
    ) -> String {
        applyTag(to: note, tag: accomplishmentTag, shouldApply: shouldApplyAccomplishmentTag(response: response, transcript: transcript))
    }

    /// Adds `ref/accomplishment` to YAML frontmatter tags when warranted.
    public static func applyAccomplishmentTag(to note: String, accomplishment: Bool) -> String {
        applyTag(to: note, tag: accomplishmentTag, shouldApply: accomplishment)
    }

    private static func applyTag(to note: String, tag: String, shouldApply: Bool) -> String {
        guard shouldApply else { return note }
        guard note.hasPrefix("---") else { return note }
        return insertTagIntoFrontmatter(note, tag: tag)
    }

    private static func insertTagIntoFrontmatter(_ note: String, tag: String) -> String {
        let lines = note.components(separatedBy: "\n")
        guard let closingIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }),
              closingIndex > 0 else {
            return note
        }

        var updated = lines

        if let tagsIndex = lines[..<closingIndex].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("tags:") }) {
            let existingTags = lines[(tagsIndex + 1)..<closingIndex]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("- ") }
                .map { String($0.dropFirst(2)) }

            guard !existingTags.contains(tag) else { return note }

            var insertAt = tagsIndex + 1
            while insertAt < closingIndex,
                  lines[insertAt].trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                insertAt += 1
            }
            updated.insert("  - \(tag)", at: insertAt)
            return updated.joined(separator: "\n")
        }

        updated.insert("  - \(tag)", at: closingIndex)
        updated.insert("tags:", at: closingIndex)
        return updated.joined(separator: "\n")
    }

    /// OpenAI structured-output schema (strict mode).
    public static let openAIResponseFormat: [String: Any] = [
        "type": "json_schema",
        "json_schema": [
            "name": "rami_daily_note_response",
            "strict": true,
            "schema": jsonSchemaObject
        ]
    ]

    private static let jsonSchemaObject: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["metadata", "reminders", "morning_mindset", "reflection", "processing_notes"],
        "properties": [
            "metadata": metadataSchema,
            "reminders": remindersSchema,
            "morning_mindset": morningMindsetSchema,
            "reflection": reflectionSchema,
            "processing_notes": ["type": ["string", "null"]]
        ]
    ]

    private static let nullableString: [String: Any] = ["type": ["string", "null"]]
    private static let nullableInteger: [String: Any] = ["type": ["integer", "null"]]
    private static let nullableBoolean: [String: Any] = ["type": ["boolean", "null"]]

    private static let ratingProperty: [String: Any] = [
        "type": ["integer", "null"],
        "description": "Rating 1-10. null if not stated in transcript."
    ]

    private static let metadataSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": [
            "dreams", "summary", "storyworthy", "accomplishment",
            "intention", "discipline", "focus", "courage", "purpose",
            "energy", "communication", "uniqueness", "rating"
        ],
        "properties": [
            "dreams": nullableString,
            "summary": nullableString,
            "storyworthy": [
                "type": ["boolean", "null"],
                "description": "true if user marks this as a storyworthy day (e.g. says @storyworthy, story worthy day, this is storyworthy). false if explicitly not. null if not mentioned."
            ],
            "accomplishment": [
                "type": ["boolean", "null"],
                "description": "true if user marks accomplishments for the day (e.g. says @accomplishment, accomplishment day, today's accomplishment). false if explicitly not. null if not mentioned."
            ],
            "intention": ratingProperty,
            "discipline": ratingProperty,
            "focus": ratingProperty,
            "courage": ratingProperty,
            "purpose": ratingProperty,
            "energy": ratingProperty,
            "communication": ratingProperty,
            "uniqueness": ratingProperty,
            "rating": ratingProperty
        ]
    ]

    private static let threeNullableStrings: [String: Any] = [
        "type": "array",
        "items": ["type": ["string", "null"]],
        "minItems": 3,
        "maxItems": 3
    ]

    private static let remindersSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["big_3", "grateful_for", "habits_planned"],
        "properties": [
            "big_3": threeNullableStrings,
            "grateful_for": threeNullableStrings,
            "habits_planned": nullableBoolean
        ]
    ]

    private static let morningMindsetSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": [
            "excited_for", "one_word_and_because", "someone_needs_me",
            "potential_obstacle", "surprise_someone", "excellence_action",
            "bold_action", "coach_would_say", "would_do_if_no_fail",
            "goal", "bottleneck", "success_criteria"
        ],
        "properties": [
            "excited_for": nullableString,
            "one_word_and_because": nullableString,
            "someone_needs_me": nullableString,
            "potential_obstacle": nullableString,
            "surprise_someone": nullableString,
            "excellence_action": nullableString,
            "bold_action": nullableString,
            "coach_would_say": nullableString,
            "would_do_if_no_fail": nullableString,
            "goal": nullableString,
            "bottleneck": nullableString,
            "success_criteria": nullableString
        ]
    ]

    private static let communicationReflectionSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["went_well", "didnt_go_well"],
        "properties": [
            "went_well": nullableString,
            "didnt_go_well": nullableString
        ]
    ]

    private static let reflectionSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": [
            "accomplishments", "what_i_controlled", "obstacles",
            "moral_compass", "improvements", "communication"
        ],
        "properties": [
            "accomplishments": nullableString,
            "what_i_controlled": nullableString,
            "obstacles": nullableString,
            "moral_compass": nullableString,
            "improvements": nullableString,
            "communication": [
                "anyOf": [
                    ["type": "null"],
                    communicationReflectionSchema
                ]
            ]
        ]
    ]

    /// Field-to-template mapping for prompts and future apply logic.
    public static let fieldGuide: String = """
    ## JSON Key → Template Mapping

    ### metadata (YAML frontmatter)
    - dreams → Dreams:
    - summary → Summary:
    - storyworthy → when true, add tag `ref/storyworthy` to YAML tags list (triggers: @storyworthy, "story worthy day", "this is storyworthy", etc.)
    - accomplishment → when true, add tag `ref/accomplishment` to YAML tags list (triggers: @accomplishment, "accomplishment day", "today's accomplishment", etc.)
    - intention → Intention:
    - discipline → Discipline:
    - focus → Focus:
    - courage → Courage:
    - purpose → Purpose:
    - energy → Energy:
    - communication → Communication:
    - uniqueness → Uniqueness:
    - rating → Rating:

    ### reminders
    - big_3[0..2] → Today's Big 3 numbered list items 1-3
    - grateful_for[0..2] → 3 things I'm grateful for (3 bullet items)
    - habits_planned → checkbox "mentally planned out how to achieve my top 5 habits"

    ### morning_mindset (each key fills the matching **bold prompt** under ### Morning Mindset)
    - excited_for → "I'm excited today for:"
    - one_word_and_because → "One word to describe the person I want to be today would be _ because:"
    - someone_needs_me → "Someone who needs me on my a-game/needs my help today is:"
    - potential_obstacle → "What's a potential obstacle/stressful situation for today and how would my best self deal with it?"
    - surprise_someone → "Someone I could surprise with a note, gift, or sign of appreciation is:"
    - excellence_action → "One action I could take today to demonstrate excellence or real value is:"
    - bold_action → "One bold/unfomfortable action I could take today is:"
    - coach_would_say → "An overseeing high performance coach would tell me today that:"
    - would_do_if_no_fail → "What would I do if I knew I wouldn't fail"
    - goal → "What is the goal?"
    - bottleneck → "What is the bottleneck?"
    - success_criteria → "I know today would be successful if I did or felt this by the end:"

    ### reflection
    - accomplishments → ### Accomplishments body
    - what_i_controlled → #### what did I control?
    - obstacles → ### Obstacles body
    - moral_compass → #### was there a situation where I went against my moral compass?
    - improvements → ### Improvements body
    - communication.went_well → #### Communication (what went well)
    - communication.didnt_go_well → #### Communication (what didn't go well)
    """
}
