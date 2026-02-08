import Foundation
import os

class JournalService: ObservableObject {
    private let vaultManager: VaultManager

    init(vaultManager: VaultManager) {
        self.vaultManager = vaultManager
    }

    // MARK: - Template Population Support

    /// Reads the existing daily note for a given date, or returns nil if it doesn't exist.
    func readDailyNote(for date: Date) throws -> String? {
        var result: String? = nil
        try vaultManager.performInVault { vaultURL in
            let fileName = Self.dateFormatter.string(from: date) + ".md"
            let noteURL = vaultURL.appendingPathComponent(fileName)

            if FileManager.default.fileExists(atPath: noteURL.path) {
                result = try String(contentsOf: noteURL, encoding: .utf8)
                Logger.journal.debug("Read existing daily note: \(fileName)")
            }
        }
        return result
    }

    /// Returns a default template for new daily notes.
    func getDefaultTemplate(for date: Date) -> String {
        let dateString = Self.dateFormatter.string(from: date)
        return """
        # Daily Note: \(dateString)

        ## Metrics
        - Mood:
        - Energy:
        - Sleep Hours:

        ## Morning Intentions

        ## Things I Learned

        ## Gratitude

        ## Tasks Completed

        ## Reflections

        """
    }

    /// Applies AI-generated template updates to a note and saves it.
    /// This method should be called AFTER getting the updates from LLMService.
    func applyTemplateUpdates(_ updates: [TemplateUpdate], to existingNote: String, for date: Date) throws {
        Logger.journal.info("Applying \(updates.count) template updates...")

        var result = existingNote

        for update in updates {
            guard let value = update.value, !value.isEmpty else { continue }

            switch update.updateType {
            case .metric:
                result = applyMetricUpdate(to: result, field: update.field, value: value)

            case .append:
                result = applyAppendUpdate(to: result, field: update.field, value: value)

            case .replace:
                result = applyReplaceUpdate(to: result, field: update.field, value: value)
            }
        }

        try saveDailyNote(content: result, for: date)
        Logger.journal.notice("Template updates applied and saved.")
    }

    private func applyMetricUpdate(to note: String, field: String, value: String) -> String {
        var lines = note.components(separatedBy: "\n")
        let normalizedField = normalizeMetricFieldName(field)

        for (index, line) in lines.enumerated() {
            guard let colonRange = line.range(of: ":") else { continue }

            let lhs = String(line[..<colonRange.lowerBound])
            let normalizedLineField = normalizeMetricFieldName(lhs)
            guard normalizedLineField.caseInsensitiveCompare(normalizedField) == .orderedSame else { continue }

            let beforeColon = String(line[..<colonRange.upperBound])
            let afterColon = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)

            if afterColon.isEmpty {
                lines[index] = beforeColon + " " + value
                Logger.journal.debug("Updated metric '\(field)' to '\(value)'")
            } else {
                Logger.journal.debug("Skipped metric '\(field)' because it already has a value")
            }
            break
        }

        return lines.joined(separator: "\n")
    }

    private func applyAppendUpdate(to note: String, field: String, value: String) -> String {
        var lines = note.components(separatedBy: "\n")
        let normalizedField = field.trimmingCharacters(in: .whitespacesAndNewlines)

        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine == normalizedField {
                var insertIndex = index + 1

                while insertIndex < lines.count {
                    let nextLine = lines[insertIndex].trimmingCharacters(in: .whitespaces)
                    if nextLine.hasPrefix("#") {
                        break
                    }
                    insertIndex += 1
                }

                let contentToInsert = value.hasPrefix("-") ? value : "- " + value
                lines.insert(contentToInsert, at: insertIndex)

                Logger.journal.debug("Appended to section '\(field)'")
                break
            }
        }

        return lines.joined(separator: "\n")
    }

    private func applyReplaceUpdate(to note: String, field: String, value: String) -> String {
        Logger.journal.debug("Replace update for '\(field)' - using append behavior for safety")
        return applyAppendUpdate(to: note, field: field, value: value)
    }

    private func saveDailyNote(content: String, for date: Date) throws {
        try vaultManager.performInVault { vaultURL in
            let fileName = Self.dateFormatter.string(from: date) + ".md"
            let noteURL = vaultURL.appendingPathComponent(fileName)
            let sanitizedContent = sanitizePersistedNoteContent(content)
            try sanitizedContent.write(to: noteURL, atomically: true, encoding: .utf8)
            Logger.journal.info("Saved daily note: \(fileName)")
        }
    }

    private func normalizeMetricFieldName(_ field: String) -> String {
        field
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#-"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Template-Based Note Creation

    /// Creates a new daily note using an inferred template
    /// - Parameters:
    ///   - date: The date for the new note
    ///   - template: The InferredTemplate to use (from VaultManager.inferredTemplate)
    /// - Throws: VaultError if vault is not configured
    func createDailyNote(for date: Date, using template: InferredTemplate) throws {
        let sanitizedTemplate = sanitizedTemplateForCreation(template)
        let renderedContent = TemplateEngine.render(sanitizedTemplate, for: date)
        try saveDailyNote(content: renderedContent, for: date)
        Logger.journal.notice("Created new daily note from inferred template for \(Self.dateFormatter.string(from: date))")
    }

    /// Gets or creates the daily note for a given date
    /// - Parameters:
    ///   - date: The date for the note
    ///   - template: Optional inferred template. If nil and note doesn't exist, uses default template.
    /// - Returns: The content of the daily note
    func getOrCreateDailyNote(for date: Date, template: InferredTemplate?) throws -> String {
        // Check if note already exists
        if let existingNote = try readDailyNote(for: date) {
            let cleanedExisting = sanitizePersistedNoteContent(existingNote)
            if cleanedExisting != existingNote {
                try saveDailyNote(content: cleanedExisting, for: date)
                Logger.journal.info("Removed inference separator markers from existing daily note.")
            }
            return cleanedExisting
        }

        // Note doesn't exist - create it
        let content: String
        if let inferredTemplate = template {
            let sanitizedTemplate = sanitizedTemplateForCreation(inferredTemplate)
            content = TemplateEngine.render(sanitizedTemplate, for: date)
            Logger.journal.info("Creating new note from inferred template")
        } else {
            content = getDefaultTemplate(for: date)
            Logger.journal.info("Creating new note from default template")
        }

        try saveDailyNote(content: content, for: date)
        return content
    }

    // MARK: - Legacy Methods (Backward Compatibility)

    func saveEntry(text: String, date: Date = Date()) async throws {
        Logger.journal.info("Starting saveEntry process...")
        let timestamp = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        let newContent = """

        ## \(timestamp) Flash Journal
        > \(text)

        """

        let existingNote = try getOrCreateDailyNote(for: date, template: vaultManager.inferredTemplate)
        try saveDailyNote(content: existingNote + newContent, for: date)
        Logger.journal.notice("Entry saved successfully.")
    }

    func saveAIEntry(originalText: String, aiResponse: AIResponse, date: Date = Date()) async throws {
        Logger.journal.info("Starting saveAIEntry process...")
        let timestamp = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        let mdContent = """

        ## \(timestamp) Voice Journal
        > \(originalText)

        ### AI Insights
        **Summary**: \(aiResponse.summary)

        **Key Realizations**:
        \(aiResponse.insights.map { "- " + $0 }.joined(separator: "\n"))

        **Action Items**:
        \(aiResponse.actionItems.map { "- [ ] " + $0 }.joined(separator: "\n"))

        **Tags**: \(aiResponse.tags.map { "#" + $0 }.joined(separator: " "))

        """

        let existingNote = try getOrCreateDailyNote(for: date, template: vaultManager.inferredTemplate)
        try saveDailyNote(content: existingNote + mdContent, for: date)
        Logger.journal.notice("AI Entry saved successfully.")
    }

    // MARK: - Helpers

    private func sanitizedTemplateForCreation(_ template: InferredTemplate) -> InferredTemplate {
        let cleanedTemplate = sanitizeTemplateString(template.template)
        let cleanedNotes = template.notes.map { sanitizeTemplateString($0) }

        guard cleanedTemplate != template.template || cleanedNotes != template.notes else {
            return template
        }

        Logger.journal.warning("Sanitized inferred template by removing transport/separator markers before rendering.")
        return InferredTemplate(
            template: cleanedTemplate,
            variables: template.variables,
            confidence: template.confidence,
            notes: cleanedNotes
        )
    }

    private func sanitizeTemplateString(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var filtered = lines.filter { !isInferenceTransportMarker($0) }

        // If model wrapped template in a markdown fence, unwrap once.
        if let first = filtered.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           let last = filtered.last?.trimmingCharacters(in: .whitespacesAndNewlines),
           first.hasPrefix("```"),
           last == "```",
           filtered.count >= 2 {
            filtered.removeFirst()
            filtered.removeLast()
        }

        let cleaned = filtered.joined(separator: "\n").trimmingCharacters(in: .newlines)
        return cleaned.isEmpty ? text : cleaned
    }

    private func sanitizePersistedNoteContent(_ text: String) -> String {
        let filtered = text
            .components(separatedBy: .newlines)
            .filter { !isInferenceTransportMarker($0) }
        let cleaned = filtered.joined(separator: "\n")
        return cleaned.isEmpty ? text : cleaned
    }

    private func isInferenceTransportMarker(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // LLM prompt sample boundary format, e.g. "=== 2026-02-06 (Friday, Week 6) ==="
        if let regex = Self.sampleBoundaryRegex {
            let range = NSRange(location: 0, length: trimmed.utf16.count)
            if regex.firstMatch(in: trimmed, options: [], range: range) != nil {
                return true
            }
        }

        // Template-var boundary format, e.g. "=== {{date:yyyy-MM-dd}} ({{weekday}}, Week {{week_number}}) ==="
        if let regex = Self.sampleBoundaryTemplateRegex {
            let range = NSRange(location: 0, length: trimmed.utf16.count)
            if regex.firstMatch(in: trimmed, options: [], range: range) != nil {
                return true
            }
        }

        // Defensive fallback for date/week style separators wrapped in === ... ===.
        if trimmed.hasPrefix("==="),
           trimmed.hasSuffix("==="),
           (trimmed.contains("Week")
            || trimmed.contains("{{date")
            || trimmed.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil) {
            return true
        }

        // Future-proof guard for explicit transport markers.
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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
