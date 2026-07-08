import SwiftUI
import os

@main
struct IgniteApp: App {
    @StateObject private var draftManager = DraftManager()
    @StateObject private var transcriberService = TranscriberService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(ThemeManager.obsidianPurple)
                .environmentObject(draftManager)
                .environmentObject(transcriberService)
                .onOpenURL { url in
                    handleOpenURL(url)
                }
                .onAppear {
                    checkForSharedContent()
                }
        }
    }

    private func handleOpenURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        // Handle text content via URL query
        if let content = components.queryItems?.first(where: { $0.name == "content" })?.value {
            appendContent(content)
            return
        }

        // Handle audio transcription
        if url.host == "transcribe-audio",
           let filename = components.queryItems?.first(where: { $0.name == "file" })?.value {
            handleAudioTranscription(filename: filename)
            return
        }

        // Fallback to App Group Defaults
        if url.host == "open-shared" {
            checkForSharedContent()
        }
    }

    private func handleAudioTranscription(filename: String) {
        print("handleAudioTranscription called for file: \(filename)")

        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.studio.orbitlabs.ignite") else {
            print("Error: Could not get shared container URL")
            return
        }

        let audioURL = sharedContainerURL.appendingPathComponent(filename)
        print("Looking for audio file at: \(audioURL.path)")

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("Error: File does not exist at path: \(audioURL.path)")
            return
        }

        Task {
            do {
                print("Starting transcription...")
                let transcription = try await transcriberService.transcribe(audioURL: audioURL)
                print("Transcription completed successfully: \(transcription.prefix(50))...")

                await MainActor.run {
                    appendContent(transcription)
                }

                // Clean up: delete the temp audio file
                try? FileManager.default.removeItem(at: audioURL)
                print("Cleaned up temp audio file")

            } catch {
                Logger.transcription.error("Share extension transcription failed: \(error.localizedDescription)")
                await MainActor.run {
                    transcriberService.shareTranscriptionError = error.localizedDescription
                }
            }
        }
    }

    private func checkForSharedContent(retryCount: Int = 0) {
        guard let defaults = UserDefaults(suiteName: "group.studio.orbitlabs.ignite") else { return }

        guard let sharedText = defaults.string(forKey: "shared_content") else {
            if retryCount < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.checkForSharedContent(retryCount: retryCount + 1)
                }
            }
            return
        }

        defaults.removeObject(forKey: "shared_content")
        defaults.synchronize()

        appendContent(sharedText)
    }

    private func appendContent(_ text: String) {
        DispatchQueue.main.async {
            if let current = self.draftManager.currentDraft {
                let newContent = current.content.isEmpty ? text : current.content + "\n\n" + text
                self.draftManager.updateCurrentDraft(content: newContent)
            } else {
                self.draftManager.createNewDraft()
                self.draftManager.updateCurrentDraft(content: text)
            }
        }
    }
}
