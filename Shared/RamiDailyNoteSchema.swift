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
    public let dreams: String?
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
    public let big3: [String?]
    public let gratefulFor: [String?]
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
    public let accomplishments: String?
    public let whatIControlled: String?
    public let obstacles: String?
    public let moralCompass: String?
    public let improvements: String?
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

// MARK: - Schema, Prompts, and Tag Application

public enum RamiDailyNoteSchema {
    public static let storyworthyTag = "ref/storyworthy"
    public static let accomplishmentTag = "ref/accomplishment"

    private static let storyworthyRegex = try? NSRegularExpression(
        pattern: #"(?i)(@storyworthy|@story[\s-]?worthy|story[\s-]?worthy\s+day|this\s+(is|was)\s+(a\s+)?story[\s-]?worthy)"#
    )

    private static let accomplishmentRegex = try? NSRegularExpression(
        pattern: #"(?i)(@accomplishment|@accomplishments|accomplishment\s+day|this\s+(is|was)\s+(an?\s+)?accomplishment|today(?:'s)?\s+accomplishment)"#
    )

    private struct RefTagRule {
        let tag: String
        let metadataFlag: Bool?
        let detector: (String) -> Bool

        func shouldApply(transcript: String) -> Bool {
            if metadataFlag == false { return false }
            if metadataFlag == true { return true }
            return detector(transcript)
        }
    }

    private static let refTagRules: [(tag: String, keyPath: KeyPath<RamiDailyNoteMetadata, Bool?>, detector: (String) -> Bool)] = [
        (storyworthyTag, \.storyworthy, detectsStoryworthy(in:)),
        (accomplishmentTag, \.accomplishment, detectsAccomplishment(in:))
    ]

    public static func detectsStoryworthy(in transcript: String) -> Bool {
        matches(storyworthyRegex, in: transcript)
    }

    public static func detectsAccomplishment(in transcript: String) -> Bool {
        matches(accomplishmentRegex, in: transcript)
    }

    public static func shouldApplyStoryworthyTag(response: RamiDailyNoteResponse, transcript: String) -> Bool {
        RefTagRule(tag: storyworthyTag, metadataFlag: response.metadata.storyworthy, detector: detectsStoryworthy(in:))
            .shouldApply(transcript: transcript)
    }

    public static func shouldApplyAccomplishmentTag(response: RamiDailyNoteResponse, transcript: String) -> Bool {
        RefTagRule(tag: accomplishmentTag, metadataFlag: response.metadata.accomplishment, detector: detectsAccomplishment(in:))
            .shouldApply(transcript: transcript)
    }

    public static func applyRefTags(
        to note: String,
        response: RamiDailyNoteResponse,
        transcript: String
    ) -> String {
        refTagRules.reduce(note) { current, rule in
            let shouldApply = RefTagRule(
                tag: rule.tag,
                metadataFlag: response.metadata[keyPath: rule.keyPath],
                detector: rule.detector
            ).shouldApply(transcript: transcript)
            return applyTag(to: current, tag: rule.tag, shouldApply: shouldApply)
        }
    }

    public static func applyStoryworthyTag(
        to note: String,
        response: RamiDailyNoteResponse,
        transcript: String
    ) -> String {
        applyTag(
            to: note,
            tag: storyworthyTag,
            shouldApply: shouldApplyStoryworthyTag(response: response, transcript: transcript)
        )
    }

    public static func applyAccomplishmentTag(
        to note: String,
        response: RamiDailyNoteResponse,
        transcript: String
    ) -> String {
        applyTag(
            to: note,
            tag: accomplishmentTag,
            shouldApply: shouldApplyAccomplishmentTag(response: response, transcript: transcript)
        )
    }

    public static func systemPrompt(dateContext: String) -> String {
        """
        You are a precision data extraction agent for a personal daily note journal.

        ## Your Mission
        Read the voice transcript and fill in ONLY the fields you can ground in what was said.
        Output a single JSON object matching the provided schema exactly.

        ## Rules
        \(extractionRules)

        \(fieldGuide)

        Current date context: \(dateContext)
        """
    }

    public static let extractionRules = """
    1. **Grounding**: Every non-null value MUST be traceable to the transcript. Never fabricate.
    2. **Null by default**: If a field is not mentioned or clearly implied, set it to null.
    3. **Ratings (1-10)**: Only set metadata ratings when the user states a number or clear score
       (e.g. "energy was a 7", "I'd give today a 6"). Do not infer ratings from mood alone.
    4. **Arrays**: big_3 and grateful_for are always length 3. Use null per slot when not mentioned.
    5. **habits_planned**: true only if the user says they planned their habits; false if they say they didn't; null if not mentioned.
    6. **communication reflection**: Set the whole `communication` object to null unless the user reflects on communication specifically. When set, use went_well and didnt_go_well sub-keys.
    7. **storyworthy**: Set `metadata.storyworthy` to true if the user marks the day as storyworthy at any point
       (e.g. "@storyworthy", "story worthy day", "this is a storyworthy day", "today was story worthy").
       Set false only if they explicitly say it is NOT storyworthy. null if not mentioned.
    8. **accomplishment**: Set `metadata.accomplishment` to true if the user marks accomplishments at any point
       (e.g. "@accomplishment", "accomplishment day", "today's accomplishment", "this is an accomplishment").
       Set false only if they explicitly say there are no accomplishments to tag. null if not mentioned.
    9. **Preserve voice**: Use the user's words where possible. Light cleanup only (punctuation, filler removal).
    10. **processing_notes**: Brief debug note listing which sections were populated.
    """

    public static let openAIResponseFormat: [String: Any] = [
        "type": "json_schema",
        "json_schema": [
            "name": "rami_daily_note_response",
            "strict": true,
            "schema": jsonSchemaObject
        ]
    ]

    public static let fieldGuide = """
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

    // MARK: - Private Helpers

    private static func matches(_ regex: NSRegularExpression?, in text: String) -> Bool {
        guard let regex else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func applyTag(to note: String, tag: String, shouldApply: Bool) -> String {
        guard shouldApply, note.hasPrefix("---") else { return note }
        return insertTagIntoFrontmatter(note, tag: tag)
    }

    private static func insertTagIntoFrontmatter(_ note: String, tag: String) -> String {
        let lines = note.components(separatedBy: "\n")
        guard let closingIndex = frontmatterClosingIndex(in: lines) else { return note }

        var updated = lines
        let frontmatterRange = 1..<closingIndex

        if let tagsIndex = frontmatterRange.first(where: { isTagsLine(lines[$0]) }) {
            let existingTags = parseYamlListTags(lines: lines, from: tagsIndex + 1, until: closingIndex)
            guard !existingTags.contains(normalizeTag(tag)) else { return note }

            var insertAt = tagsIndex + 1
            while insertAt < closingIndex, isYamlListItem(lines[insertAt]) {
                insertAt += 1
            }
            updated.insert("  - \(tag)", at: insertAt)
            return updated.joined(separator: "\n")
        }

        updated.insert("  - \(tag)", at: closingIndex)
        updated.insert("tags:", at: closingIndex)
        return updated.joined(separator: "\n")
    }

    private static func frontmatterClosingIndex(in lines: [String]) -> Int? {
        guard lines.first.map({ isFrontmatterDelimiter($0) }) == true else { return nil }
        guard let closingIndex = lines.dropFirst().firstIndex(where: { isFrontmatterDelimiter($0) }) else {
            return nil
        }
        // dropFirst offset: index 0 is opening ---, so closing is dropFirst index + 1
        return closingIndex + 1
    }

    private static func isFrontmatterDelimiter(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "---"
    }

    private static func isTagsLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("tags:")
    }

    private static func isYamlListItem(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("- ")
    }

    private static func parseYamlListTags(lines: [String], from start: Int, until end: Int) -> Set<String> {
        guard start < end else { return [] }
        return Set(
            lines[start..<end]
                .filter(isYamlListItem)
                .map { normalizeTag(String($0.trimmingCharacters(in: .whitespaces).dropFirst(2))) }
        )
    }

    private static func normalizeTag(_ tag: String) -> String {
        tag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static let nullableString: [String: Any] = ["type": ["string", "null"]]
    private static let nullableBoolean: [String: Any] = ["type": ["boolean", "null"]]

    private static let ratingProperty: [String: Any] = [
        "type": ["integer", "null"],
        "description": "Rating 1-10. null if not stated in transcript."
    ]

    private static let nullableTagFlagProperty: [String: Any] = [
        "type": ["boolean", "null"]
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
            "storyworthy": nullableTagFlagProperty.merging([
                "description": "true if user marks this as a storyworthy day (e.g. @storyworthy). false if explicitly not. null if not mentioned."
            ]) { _, new in new },
            "accomplishment": nullableTagFlagProperty.merging([
                "description": "true if user marks accomplishments (e.g. @accomplishment). false if explicitly not. null if not mentioned."
            ]) { _, new in new },
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
}
