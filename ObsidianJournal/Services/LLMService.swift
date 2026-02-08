import Foundation
import os

// Models are defined in Shared/AIModels.swift

// MARK: - LLM Service

class LLMService: ObservableObject {
    private let endpoint = "https://api.openai.com/v1/chat/completions"

    // MARK: - Template Population (New Primary Method)

    /// Analyzes a transcript and existing daily note template, returning structured updates.
    /// This is the core "template hydration" engine.
    func populateTemplate(transcript: String, existingNote: String, date: Date = Date()) async throws -> TemplatePopulationResponse {
        Logger.ai.info("Starting template population. Transcript: \(transcript.count) chars, Note: \(existingNote.count) chars")

        guard let apiKey = KeychainManager.shared.getAPIKey(), !apiKey.isEmpty else {
            throw LLMError.missingAPIKey
        }

        let dateString = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        let allowedFields = extractTemplateFields(from: existingNote)
        let allowedFieldsText = allowedFields.isEmpty
            ? "- (no explicit fields detected)"
            : allowedFields.map { "- \($0)" }.joined(separator: "\n")

        // ═══════════════════════════════════════════════════════════════════════════════
        // SYSTEM PROMPT - The Heart of the Template Population Engine
        // ═══════════════════════════════════════════════════════════════════════════════
        let systemPrompt = """
        You are a precision data extraction agent for an Ignite journaling system.

        ## Your Mission
        Analyze the user's voice transcript and intelligently populate sections of their existing daily note template. Extract ONLY information that is explicitly stated or directly implied in the transcript. Never fabricate, assume, or hallucinate data.

        ## Operating Principles
        1. **Grounding Rule**: Every value you output MUST be traceable to the transcript. If you cannot quote or paraphrase the source, output null for that field.
        2. **Respect the Template**: Only populate fields that exist in the provided template. Do not invent new sections.
        3. **Preserve Existing Data**: If a section already has content, use "append" to add new information. Use "replace" only if the transcript explicitly supersedes existing data.
        4. **Type Awareness**:
           - Text sections (## headings, bullet lists): Use "append" type with properly formatted markdown.
           - Metrics (numbers, scores, durations): Use "metric" type with the numeric value as a string.
           - Yes/No fields: Use "metric" type with "true"/"false".
        5. **Silence is Golden**: If the transcript contains no relevant information for a template section, DO NOT include that field in your output. An empty update list is valid.
        6. **Field Whitelist (Strict)**: The "field" value MUST exactly match one of the allowed fields provided by the user message.
        7. **Structure Protection**: Never rewrite or regenerate the template. Return only granular updates.

        ## Output Schema (JSON)
        ```json
        {
          "updates": [
            {
              "field": "Exact heading or field name from template",
              "value": "The extracted content, formatted appropriately, or null if nothing applies",
              "updateType": "append" | "replace" | "metric"
            }
          ],
          "processing_notes": "Brief internal note about what was extracted (for debugging)"
        }
        ```

        ## Examples

        ### Example 1: Metrics Extraction
        **Template Section**: `Sleep Hours: `
        **Transcript**: "I got about 7 hours of sleep last night, felt pretty good."
        **Output**:
        ```json
        {"field": "Sleep Hours", "value": "7", "updateType": "metric"}
        ```

        ### Example 2: Text Section Append
        **Template Section**: `## Things I Learned`
        **Transcript**: "Today I realized that consistency beats intensity in habit formation."
        **Output**:
        ```json
        {"field": "## Things I Learned", "value": "- Consistency beats intensity in habit formation", "updateType": "append"}
        ```

        ### Example 3: No Relevant Data
        **Template Section**: `## Exercise Log`
        **Transcript**: "Had a really productive day at work coding."
        **Output**: Do not include "## Exercise Log" in the updates array.

        ### Example 4: Multiple Updates
        **Template**:
        ```
        Mood:
        ## Gratitude
        ## Tasks Completed
        ```
        **Transcript**: "Feeling great today, probably an 8 out of 10. Really grateful for the sunny weather. Finished the project proposal and sent it off."
        **Output**:
        ```json
        {
          "updates": [
            {"field": "Mood", "value": "8", "updateType": "metric"},
            {"field": "## Gratitude", "value": "- Sunny weather", "updateType": "append"},
            {"field": "## Tasks Completed", "value": "- Finished and sent project proposal", "updateType": "append"}
          ],
          "processing_notes": "Extracted mood score, gratitude item, and task completion."
        }
        ```

        ## Critical Reminders
        - **NEVER** make up information not in the transcript.
        - **ALWAYS** use the exact field name from the template.
        - Format bullet points with `- ` prefix for text sections.
        - If a mapping is uncertain, skip it.
        - Do not emit duplicate updates for the same field unless both are clearly necessary.
        - For empty templates, focus on extracting whatever is mentioned.
        - Current date context: \(dateString)
        """

        // ═══════════════════════════════════════════════════════════════════════════════
        // USER PROMPT - Provides the Actual Data
        // ═══════════════════════════════════════════════════════════════════════════════
        let userPrompt = """
        ## EXISTING DAILY NOTE TEMPLATE
        ```markdown
        \(existingNote)
        ```

        ## ALLOWED FIELDS (STRICT WHITELIST)
        \(allowedFieldsText)

        ## VOICE TRANSCRIPT TO PROCESS
        ```
        \(transcript)
        ```

        Analyze the transcript above. Extract only information that maps to the template and allowed-field whitelist. Output valid JSON only.
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.2 // Low temperature for factual extraction
        ]

        return try await executeRequest(requestBody: requestBody, responseType: TemplatePopulationResponse.self)
    }

    // MARK: - Template Inference

    /// Analyzes sample daily notes and infers the template structure with date-based variables
    /// - Parameter samples: Array of DailyNoteSample from recent daily notes (ideally 3-5 days)
    /// - Returns: InferredTemplate with detected placeholders
    func inferTemplate(from samples: [DailyNoteSample]) async throws -> InferredTemplate {
        Logger.ai.info("Starting template inference from \(samples.count) sample notes")

        guard !samples.isEmpty else {
            Logger.ai.warning("No samples provided, returning default template")
            return InferredTemplate(
                template: "# {{date:yyyy-MM-dd}}\n\n## Journal\n\n",
                variables: [TemplateVariable(name: "date", format: "yyyy-MM-dd", description: "Current date")],
                confidence: 0.5,
                notes: "Default template - no samples available"
            )
        }

        guard let apiKey = KeychainManager.shared.getAPIKey(), !apiKey.isEmpty else {
            throw LLMError.missingAPIKey
        }

        // Build the sample notes string with date context
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEEE"

        var samplesText = ""
        for sample in samples {
            let dateStr = dateFormatter.string(from: sample.date)
            let weekdayStr = weekdayFormatter.string(from: sample.date)
            let calendar = Calendar.current
            let weekOfYear = calendar.component(.weekOfYear, from: sample.date)

            samplesText += """
            === \(dateStr) (\(weekdayStr), Week \(weekOfYear)) ===
            \(sample.content)

            """
        }

        let systemPrompt = """
        You are a template pattern recognition agent. Your task is to analyze multiple daily notes from an Obsidian vault and infer the underlying template structure.

        ## Your Mission
        1. Identify what content stays CONSTANT across all notes (the template structure)
        2. Identify what content CHANGES based on the date (variables that need placeholders)
        3. Output a reusable template with {{variable:format}} placeholders

        ## Supported Variables
        You can use these placeholder patterns:
        - {{date:FORMAT}} - The current date, e.g., {{date:yyyy-MM-dd}} → 2026-01-08
        - {{weekday}} - Full weekday name, e.g., Wednesday
        - {{weekday_short}} - Short weekday, e.g., Wed
        - {{yesterday:FORMAT}} - Yesterday's date
        - {{tomorrow:FORMAT}} - Tomorrow's date
        - {{week_number}} - ISO week number, e.g., 2
        - {{year}} - 4-digit year, e.g., 2026
        - {{month}} - Full month name, e.g., January
        - {{month_short}} - Short month, e.g., Jan
        - {{day}} - Day of month number, e.g., 8

        ## Output Schema (JSON)
        ```json
        {
          "template": "The full template string with {{variable}} placeholders",
          "variables": [
            {
              "name": "variable_name",
              "format": "format_string or null",
              "description": "What this variable represents"
            }
          ],
          "confidence": 0.0-1.0,
          "notes": "Explanation of patterns detected"
        }
        ```

        ## Rules
        1. Look for date patterns in titles, headers, and navigation links (like [[2026-01-07]] ← [[2026-01-09]])
        2. Preserve the exact markdown structure - headers, bullet points, spacing
        3. Keep any static text that appears identically in all samples
        4. Remove user-entered content (journal entries, completed tasks) - leave sections empty
        5. If you see patterns like "Week 1" or "Week 52", use {{week_number}}
        6. For navigation links, use {{yesterday:format}} and {{tomorrow:format}}
        7. Set confidence based on how consistent the patterns are across samples
        8. The lines formatted like "=== 2026-02-06 (Friday, Week 6) ===" are sample separators, not note content. NEVER include them in the template.
        9. Do not wrap the template in markdown code fences.

        ## Example Detection
        If you see across 3 notes:
        - "# 2026-01-05 | Friday"
        - "# 2026-01-06 | Saturday"
        - "# 2026-01-07 | Sunday"

        The template should be: "# {{date:yyyy-MM-dd}} | {{weekday}}"
        """

        let userPrompt = """
        Analyze these \(samples.count) daily notes and infer the template structure:

        \(samplesText)

        Output the inferred template as valid JSON.
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.1 // Very low temperature for consistent pattern matching
        ]

        let response = try await executeRequest(requestBody: requestBody, responseType: InferredTemplate.self)
        let sanitized = sanitizeInferredTemplate(response)
        Logger.ai.notice("Template inference complete. Confidence: \(sanitized.confidence)")
        return sanitized
    }

    // MARK: - Legacy Method (Simple Insight Extraction)

    /// Original method for backward compatibility - extracts insights without template context.
    func processJournalEntry(text: String) async throws -> AIResponse {
        Logger.ai.info("Starting legacy AI processing for text length: \(text.count)")

        guard let apiKey = KeychainManager.shared.getAPIKey(), !apiKey.isEmpty else {
            throw LLMError.missingAPIKey
        }

        let dateString = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)

        let systemPrompt = """
        You are an intelligent journaling assistant. Your job is to analyze the user's stream-of-consciousness entry and extract structured insights.

        Output valid JSON only matching this schema:
        {
          "summary": "2-3 sentences summarizing the entry",
          "insights": ["List of key realizations or patterns"],
          "action_items": ["List of actionable tasks mentioned or implied"],
          "tags": ["List of 3-5 relevant hashtags without # symbol"]
        }

        Only include information explicitly stated or directly implied. Do not fabricate.
        """

        let userPrompt = "Date: \(dateString)\n\nJournal Entry:\n\(text)"

        let requestBody: [String: Any] = [
            "model": "gpt-5.2",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.3
        ]

        return try await executeRequest(requestBody: requestBody, responseType: AIResponse.self)
    }

    // MARK: - Private Helpers

    private func extractTemplateFields(from note: String) -> [String] {
        var fields: [String] = []
        var seen: Set<String> = []

        for rawLine in note.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("#") {
                if seen.insert(trimmed).inserted {
                    fields.append(trimmed)
                }
                continue
            }

            guard let metricField = extractMetricField(from: trimmed) else { continue }
            if seen.insert(metricField).inserted {
                fields.append(metricField)
            }
        }

        return fields
    }

    private func extractMetricField(from line: String) -> String? {
        var candidate = line
        if candidate.hasPrefix("- ") {
            candidate.removeFirst(2)
        }

        guard let colon = candidate.firstIndex(of: ":") else { return nil }
        let name = String(candidate[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        guard name.count <= 80 else { return nil }
        return name
    }

    private func sanitizeInferredTemplate(_ template: InferredTemplate) -> InferredTemplate {
        let cleanedTemplate = sanitizeInferredTemplateText(template.template)
        let cleanedNotes = template.notes.map { sanitizeInferredTemplateText($0) }

        guard cleanedTemplate != template.template || cleanedNotes != template.notes else {
            return template
        }

        Logger.ai.warning("Sanitized inferred template by removing separator/transport markers.")
        return InferredTemplate(
            template: cleanedTemplate,
            variables: template.variables,
            confidence: template.confidence,
            notes: cleanedNotes
        )
    }

    private func sanitizeInferredTemplateText(_ text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        lines.removeAll { isInferenceSeparatorLine($0) }

        // Unwrap one outer code fence if present.
        if let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           let last = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines),
           first.hasPrefix("```"),
           last == "```",
           lines.count >= 2 {
            lines.removeFirst()
            lines.removeLast()
        }

        let cleaned = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
        return cleaned.isEmpty ? text : cleaned
    }

    private func isInferenceSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if let regex = Self.sampleBoundaryRegex {
            let range = NSRange(location: 0, length: trimmed.utf16.count)
            if regex.firstMatch(in: trimmed, options: [], range: range) != nil {
                return true
            }
        }

        if let regex = Self.sampleBoundaryTemplateRegex {
            let range = NSRange(location: 0, length: trimmed.utf16.count)
            if regex.firstMatch(in: trimmed, options: [], range: range) != nil {
                return true
            }
        }

        if trimmed.hasPrefix("==="),
           trimmed.hasSuffix("==="),
           (trimmed.contains("Week")
            || trimmed.contains("{{date")
            || trimmed.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil) {
            return true
        }

        if trimmed.hasPrefix("<<<") && trimmed.hasSuffix(">>>") {
            return true
        }

        return false
    }

    private static let sampleBoundaryRegex = try? NSRegularExpression(
        pattern: #"^===\s*\d{4}-\d{2}-\d{2}\s*\([^)]+\)\s*===\s*$"#
    )

    private static let sampleBoundaryTemplateRegex = try? NSRegularExpression(
        pattern: #"^===\s*\{\{date:[^}]+\}\}\s*\([^)]+\)\s*===\s*$"#
    )

    private func executeRequest<T: Decodable>(requestBody: [String: Any], responseType: T.Type) async throws -> T {
        guard let apiKey = KeychainManager.shared.getAPIKey() else {
            throw LLMError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        Logger.ai.debug("Sending request to OpenAI...")
        let (data, response) = try await URLSession.shared.data(for: request)

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.ai.error("API Error: \(statusCode) - \(body)")
            throw LLMError.apiError(statusCode: statusCode, message: body)
        }

        do {
            let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            guard let jsonString = chatResponse.choices.first?.message.content,
                  let jsonData = jsonString.data(using: .utf8) else {
                Logger.ai.error("Invalid response format from OpenAI")
                throw LLMError.invalidResponse
            }

            let result = try JSONDecoder().decode(T.self, from: jsonData)
            Logger.ai.notice("Successfully parsed AI response of type \(String(describing: T.self)).")
            return result
        } catch {
            Logger.ai.fault("JSON Decoding Error: \(error.localizedDescription)")
            throw error
        }
    }
}

// MARK: - OpenAI Response Structure

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

// MARK: - Errors

enum LLMError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Please add your OpenAI API Key in Settings."
        case .invalidResponse: return "The AI returned an invalid response."
        case .apiError(let code, let msg): return "AI Error (\(code)): \(msg)"
        }
    }
}
