import SwiftUI
import AVFoundation

struct MainEditorView: View {
    @EnvironmentObject var draftManager: DraftManager
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var transcriberService = TranscriberService()
    @EnvironmentObject var journalService: JournalService
    @EnvironmentObject var vaultManager: VaultManager // Access to shared VaultManager

    // UI State
    @State private var showDrafts = false
    @State private var showArchive = false
    @State private var showSettings = false

    // Text Editor State
    @State private var cursorPosition: Int = 0
    @State private var isDictating = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.primary.colorInvert().ignoresSafeArea() // Background

                VStack(spacing: 0) {
                    // Editor Area
                    if let draft = draftManager.currentDraft {
                        CursorAwareTextEditor(
                            text: Binding(
                                get: { draft.content },
                                set: { draftManager.updateCurrentDraft(content: $0) }
                            ),
                            cursorPosition: $cursorPosition,
                            isEditable: !audioRecorder.isRecording
                        )
                        .padding(.horizontal)
                    } else {
                        // Fallback if no draft (shouldn't happen)
                        Text("No Draft Selected")
                            .foregroundColor(.secondary)
                    }
                }

                // Bottom Floating Bar
                VStack {
                    Spacer()
                    HStack(spacing: 20) {
                        // Dictate / Stop Button
                        Button(action: toggleRecording) {
                            HStack {
                                Image(systemName: audioRecorder.isRecording ? "stop.fill" : "mic.fill")
                                    .font(.title2)
                                if audioRecorder.isRecording {
                                    Text("Stop")
                                        .fontWeight(.semibold)
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 24)
                            .background(
                                Capsule()
                                    .fill(audioRecorder.isRecording ? Color.red : ThemeManager.obsidianPurple)
                                    .shadow(color: (audioRecorder.isRecording ? Color.red : ThemeManager.obsidianPurple).opacity(0.3), radius: 10, x: 0, y: 5)
                            )
                        }

                        // Submit Button (only if content exists)
                        if let content = draftManager.currentDraft?.content, !content.isEmpty {
                            Button(action: submitEntry) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .resizable()
                                    .frame(width: 50, height: 50)
                                    .foregroundColor(.green)
                                    .background(Circle().fill(Color.white))
                                    .shadow(radius: 5)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.bottom, 20)
                }

                // Model Loading Status Banner
                if case .loading = transcriberService.modelLoadingState {
                    VStack {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(.white)
                            Text("Loading transcription model...")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(ThemeManager.obsidianPurple.opacity(0.9))
                                .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                        )
                        .padding(.top, 8)

                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: transcriberService.modelLoadingState)
                }

                // Transcribing Status Banner
                if transcriberService.isTranscribing {
                    VStack {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(.white)
                            Text("Transcribing...")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.9))
                                .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                        )
                        .padding(.top, 8)

                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: transcriberService.isTranscribing)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        Button(action: { setDate(offset: 0) }) {
                            Label(getDateLabel(for: 0), systemImage: "calendar")
                        }
                        Button(action: { setDate(offset: -1) }) {
                            Label(getDateLabel(for: -1), systemImage: "clock.arrow.circlepath")
                        }
                        Button(action: { setDate(offset: 1) }) {
                            Label(getDateLabel(for: 1), systemImage: "arrow.turn.up.right")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(headerTitle)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showDrafts.toggle() }) {
                        Image(systemName: "sidebar.left")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: { showArchive.toggle() }) {
                            Image(systemName: "archivebox")
                        }
                        Button(action: { showSettings.toggle() }) {
                            Image(systemName: "gearshape")
                        }
                    }
                }

                // Keyboard Toolbar
                ToolbarItemGroup(placement: .keyboard) {
                     Spacer()

                     // Mic Button
                     Button(action: toggleRecording) {
                         HStack(spacing: 6) {
                             Image(systemName: audioRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                 .foregroundColor(audioRecorder.isRecording ? .red : ThemeManager.obsidianPurple)
                             Text(audioRecorder.isRecording ? "Stop" : "Dictate")
                                 .foregroundColor(audioRecorder.isRecording ? .red : .primary)
                         }
                         .padding(.horizontal, 12)
                         .padding(.vertical, 6)
                         .background(Material.thin)
                         .clipShape(Capsule())
                     }

                     Spacer()

                     // Submit Button
                     if let content = draftManager.currentDraft?.content, !content.isEmpty {
                         Button(action: submitEntry) {
                             HStack(spacing: 6) {
                                 Text("Submit")
                                 Image(systemName: "arrow.up.circle.fill")
                             }
                             .foregroundColor(.green)
                             .padding(.horizontal, 12)
                             .padding(.vertical, 6)
                             .background(Material.thin)
                             .clipShape(Capsule())
                         }
                     }
                }
            }
            .sheet(isPresented: $showDrafts) {
                DraftsListView(draftManager: draftManager, isPresented: $showDrafts)
            }
            .sheet(isPresented: $showArchive) {
                ArchiveListView(draftManager: draftManager, isPresented: $showArchive)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .onReceive(audioRecorder.$recordingURL) { url in
            // When recording stops and URL is set, trigger transcription
            if let url = url, !audioRecorder.isRecording {
                processTranscription(url: url)
            }
        }
        .onAppear {
            // Set cursor to end of existing draft so transcriptions append by default
            if let draft = draftManager.currentDraft {
                cursorPosition = draft.content.count
            }
        }
    }

    // MARK: - Actions

    private func toggleRecording() {
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
            isDictating = false
        } else {
            audioRecorder.startRecording()
            isDictating = true
        }
    }

    private func processTranscription(url: URL) {
        Task {
            do {
                var text = try await transcriberService.transcribe(audioURL: url)

                // remove [BLANK_AUDIO] from text
                text = text.replacingOccurrences(of: "[BLANK_AUDIO]", with: "")

                // Skip blank transcriptions - only insert real text
                guard !text.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    print("Skipping empty transcription")
                    return
                }

                // Insert text at cursor position
                await MainActor.run {
                    guard let draft = draftManager.currentDraft else { return }
                    var newContent = draft.content

                    // Simple insertion logic
                    // Ensure we handle index correctly (Swift String indices are tricky)
                    if cursorPosition > newContent.count {
                        cursorPosition = newContent.count
                    }
                    let index = newContent.index(newContent.startIndex, offsetBy: cursorPosition)

                    // Add space if needed
                    let textToInsert = (cursorPosition > 0 ? " " : "") + text

                    newContent.insert(contentsOf: textToInsert, at: index)
                    draftManager.updateCurrentDraft(content: newContent)

                    // Move cursor
                    cursorPosition += textToInsert.count
                }
            } catch {
                print("Transcription error: \(error)")
            }
        }
    }

    private func submitEntry() {
        guard let draft = draftManager.currentDraft else { return }

        Task {
            do {
                let llmService = LLMService()
                let date = draft.createdAt.journalDate

                // Step 1: Ensure daily note exists from the canonical template path.
                // If missing, this creates it from inferred template (or default fallback) first.
                let existingNote = try journalService.getOrCreateDailyNote(
                    for: date,
                    template: vaultManager.inferredTemplate
                )

                // Step 2: Call AI to extract structured updates from transcript
                let populationResponse = try await llmService.populateTemplate(
                    transcript: draft.content,
                    existingNote: existingNote,
                    date: date
                )

                // Step 3: Apply updates to the note
                try journalService.applyTemplateUpdates(
                    populationResponse.updates,
                    to: existingNote,
                    for: date
                )

                // Step 4: Archive the draft
                await MainActor.run {
                    draftManager.archiveDraft(draft)
                }
            } catch {
                print("Submission failed: \(error)")
                // TODO: Show error alert
            }
        }
    }
    private func setDate(offset: Int) {
        let calendar = Calendar.current
        let today = Date()

        // Calculate target date
        let targetDate: Date
        if offset == 0 {
            targetDate = today
        } else {
            targetDate = calendar.date(byAdding: .day, value: offset, to: today) ?? today
        }

        draftManager.updateDraftDate(targetDate)
    }

    private func getDateLabel(for offset: Int) -> String {
        let calendar = Calendar.current
        let today = Date()
        let targetDate: Date

        if offset == 0 {
            targetDate = today
        } else {
            targetDate = calendar.date(byAdding: .day, value: offset, to: today) ?? today
        }

        let prefix: String
        if offset == 0 {
            prefix = "Today"
        } else if offset == -1 {
            prefix = "Yesterday"
        } else if offset == 1 {
            prefix = "Tomorrow"
        } else {
            return targetDate.formatted(date: .abbreviated, time: .omitted)
        }

        return "\(prefix), \(targetDate.ordinalDateString)"
    }

    private var headerTitle: String {
        guard let rawDate = draftManager.currentDraft?.createdAt else { return "Journal" }
        let date = rawDate.journalDate
        let calendar = Calendar.current

        // Check relative dates
        if calendar.isDateInToday(date) {
            return "Today, \(date.ordinalDateString)"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday, \(date.ordinalDateString)"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow, \(date.ordinalDateString)"
        } else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}
