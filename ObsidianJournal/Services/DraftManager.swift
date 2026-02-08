import Foundation
import Combine
import os

class DraftManager: ObservableObject {
    @Published var drafts: [Draft] = []
    @Published var currentDraft: Draft?

    private let draftsFileName = "drafts.json"

    // Computed properties for views
    var activeDrafts: [Draft] {
        drafts.filter { $0.status == .draft }
    }

    var archivedDrafts: [Draft] {
        drafts.filter { $0.status == .archived }
    }

    init() {
        loadDrafts()
        cleanupOnLaunch()

        // Ensure there is at least one draft (the current active one) or create a new one
        if let lastEdited = activeDrafts.sorted(by: { $0.modifiedAt > $1.modifiedAt }).first {
            self.currentDraft = lastEdited
        } else {
            createNewDraft()
        }

        Logger.ui.debug("DraftManager initialized. Total count: \(self.drafts.count). Active: \(self.activeDrafts.count)")
    }

    private func cleanupOnLaunch() {
        // Remove empty drafts on launch, except if it's the only one?
        // Actually, just remove all empty ones. The init logic below will create one if needed.
        let originalCount = drafts.count
        drafts.removeAll { $0.status == .draft && $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if drafts.count != originalCount {
            saveDrafts()
            Logger.ui.info("Cleaned up \(originalCount - self.drafts.count) empty drafts on launch.")
        }
    }

    func createNewDraft() {
        // Reuse current if empty
        if let current = currentDraft, current.status == .draft, current.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Logger.ui.info("Reusing current empty draft: \(current.id)")
            return
        }

        // Also cleanup any other stray empty drafts before adding a new one
        cleanupEmptyDrafts()

        let newDraft = Draft()
        drafts.append(newDraft)
        currentDraft = newDraft
        saveDrafts()
        Logger.ui.info("Created new draft: \(newDraft.id)")
    }

    private var saveDebounceTask: Task<Void, Never>?

    func updateCurrentDraft(content: String) {
        guard var draft = currentDraft else { return }
        draft.content = content
        draft.modifiedAt = Date()

        // Trigger UI update FIRST (before any disk I/O)
        objectWillChange.send()

        // Update local state
        currentDraft = draft

        // Update in array
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index] = draft
        } else {
            drafts.append(draft)
        }

        // Debounce disk save - only save after 1 second of inactivity
        saveDebounceTask?.cancel()
        saveDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.saveDrafts()
            }
        }
    }

    func updateDraftDate(_ date: Date) {
        guard var draft = currentDraft else { return }
        let calendar = Calendar.current
        // Normalize to midday so journal-day logic doesn't shift selected dates.
        let normalizedDate = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        draft.createdAt = normalizedDate
        draft.modifiedAt = Date()

        objectWillChange.send()
        currentDraft = draft

        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index] = draft
        }

        saveDrafts()
    }

    func archiveDraft(_ draft: Draft) {
        guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }

        var archivedDraft = drafts[index]
        archivedDraft.status = .archived
        archivedDraft.modifiedAt = Date()

        drafts[index] = archivedDraft

        // If the archived draft was current, create a new one
        if currentDraft?.id == draft.id {
            createNewDraft()
        }

        saveDrafts()
        Logger.ui.info("Archived draft: \(draft.id)")
    }

    func restoreDraft(_ draft: Draft) {
        // When restoring, we might be navigating to it.
        // We should check if the CURRENT (pre-restore) draft is empty and should be cleaned up.
        cleanupEmptyDrafts()

        guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }

        var restoredDraft = drafts[index]
        restoredDraft.status = .draft
        restoredDraft.modifiedAt = Date()

        drafts[index] = restoredDraft
        saveDrafts()
        Logger.ui.info("Restored draft: \(draft.id)")
    }

    func deleteDraft(_ draft: Draft) {
        drafts.removeAll { $0.id == draft.id }
        // If we deleted the current draft, check if we have any other active drafts
        if currentDraft?.id == draft.id {
            if let nextDraft = activeDrafts.first {
                currentDraft = nextDraft
            } else {
                createNewDraft()
            }
        }
        saveDrafts()
        Logger.ui.info("Deleted draft: \(draft.id)")
    }

    func selectDraft(_ draft: Draft) {
        // Before switching, check if the *current* draft is empty and should be discarded
        if let oldDraft = currentDraft, oldDraft.id != draft.id, oldDraft.status == .draft {
            if oldDraft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Delete the old empty draft
                Logger.ui.info("Auto-deleting empty draft: \(oldDraft.id)")
                drafts.removeAll { $0.id == oldDraft.id }
            }
        }

        self.currentDraft = draft
        saveDrafts()
        Logger.ui.debug("Selected draft: \(draft.id)")
    }

    private func cleanupEmptyDrafts() {
        // Removes empty drafts that are NOT the current one (safety)
        // Or actually, remove ANY empty draft that isn't the one we are about to switch TO.
        // But for generic cleanup:
        let emptyDrafts = drafts.filter { $0.status == .draft && $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.id != currentDraft?.id }

        for draft in emptyDrafts {
             drafts.removeAll { $0.id == draft.id }
             Logger.ui.info("Cleaned up background empty draft: \(draft.id)")
        }
    }

    // MARK: - Persistence

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func saveDrafts() {
        let url = getDocumentsDirectory().appendingPathComponent(draftsFileName)
        do {
            let data = try JSONEncoder().encode(drafts)
            try data.write(to: url)
        } catch {
            Logger.ui.error("Failed to save drafts: \(error.localizedDescription)")
        }
    }

    private func loadDrafts() {
        let url = getDocumentsDirectory().appendingPathComponent(draftsFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            drafts = try JSONDecoder().decode([Draft].self, from: data)
            Logger.ui.info("Loaded \(self.drafts.count) drafts.")
        } catch {
            Logger.ui.error("Failed to load drafts: \(error.localizedDescription)")
        }
    }
}
