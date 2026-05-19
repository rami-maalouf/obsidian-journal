import SwiftUI
import AVFoundation
import os
import UIKit

struct MainEditorView: View {
    @EnvironmentObject var draftManager: DraftManager
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var transcriberService = TranscriberService()
    @EnvironmentObject var journalService: JournalService
    @EnvironmentObject var vaultManager: VaultManager // Access to shared VaultManager

    // UI State
    @State private var isSidebarOpen = false
    @State private var sidebarDragTranslation: CGFloat = 0
    @State private var showArchive = false
    @State private var showSettings = false

    // Text Editor State
    @State private var cursorPosition: Int = 0
    @State private var isDictating = false
    @State private var activeRecordingSignature: String?
    @State private var lastCompletedRecordingSignature: String?
    @State private var shareSheetPayload: ShareSheetPayload?
    @State private var isExportingAudio = false
    @State private var audioShareError: String?
    @State private var transcriptionError: String?

    var body: some View {
        GeometryReader { geometry in
            let pageWidth = geometry.size.width
            let offset = pageOffset(pageWidth: pageWidth)

            HStack(spacing: 0) {
                NavigationStack {
                    DraftsListView(
                        draftManager: draftManager,
                        onSelectDraft: { draft in
                            draftManager.selectDraft(draft)
                            closeSidebar()
                        },
                        onCreateDraft: {
                            draftManager.createNewDraft()
                            closeSidebar()
                        }
                    )
                    .navigationTitle("Drafts")
                }
                .frame(width: pageWidth, height: geometry.size.height)
                .background(Color(.systemGroupedBackground))

                NavigationStack {
                    editorContent
                }
                .frame(width: pageWidth, height: geometry.size.height)
                .background(Color(.systemBackground))
            }
            .offset(x: offset)
            .frame(width: pageWidth, height: geometry.size.height, alignment: .leading)
            .background(Color(.systemGroupedBackground))
            .contentShape(Rectangle())
            .gesture(sidebarDragGesture(pageWidth: pageWidth))
            .animation(.snappy(duration: 0.28), value: isSidebarOpen)
            .ignoresSafeArea(.keyboard, edges: .bottom)
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

    private var editorContent: some View {
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

            bottomFloatingBar
            statusBanners
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            editorToolbar
        }
        .sheet(isPresented: $showArchive) {
            ArchiveListView(draftManager: draftManager, isPresented: $showArchive)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $shareSheetPayload) { payload in
            ActivityView(activityItems: payload.items)
        }
        .alert("Audio Sharing Failed", isPresented: audioShareErrorBinding) {
            Button("OK", role: .cancel) {
                audioShareError = nil
            }
        } message: {
            Text(audioShareError ?? "")
        }
        .alert("Transcription Failed", isPresented: transcriptionErrorBinding) {
            Button("OK", role: .cancel) {
                transcriptionError = nil
            }
        } message: {
            Text(transcriptionError ?? "")
        }
    }

    private var bottomFloatingBar: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                if let draft = draftManager.currentDraft {
                    HStack(spacing: 10) {
                        if draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            actionButton(
                                title: "Share Text",
                                systemImage: "text.quote",
                                isDisabled: true,
                                action: {}
                            )
                        } else {
                            ShareLink(item: draft.content) {
                                actionLabel(title: "Share Text", systemImage: "text.quote")
                            }
                            .buttonStyle(.bordered)
                        }

                        Button(action: shareCurrentAudio) {
                            actionLabel(
                                title: isExportingAudio ? "Preparing..." : "Share Audio",
                                systemImage: "waveform"
                            )
                        }
                        .buttonStyle(.bordered)
                        .disabled(draft.recordings.isEmpty || isExportingAudio)

                        Button(action: submitEntry) {
                            actionLabel(title: "Send", systemImage: "arrow.up.doc")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .tint(.green)
                    }

                    if draft.recordings.isEmpty {
                        Text("No audio saved yet")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

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
                }
            }
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var statusBanners: some View {
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

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
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
            Button(action: openSidebar) {
                Image(systemName: "sidebar.left")
            }
            .accessibilityLabel("Show Drafts")
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

    // MARK: - Actions

    private func openSidebar() {
        withAnimation {
            isSidebarOpen = true
        }
    }

    private func closeSidebar() {
        withAnimation {
            isSidebarOpen = false
        }
    }

    private func pageOffset(pageWidth: CGFloat) -> CGFloat {
        let baseOffset = isSidebarOpen ? 0 : -pageWidth
        return clamped(baseOffset + sidebarDragTranslation, lower: -pageWidth, upper: 0)
    }

    private func sidebarDragGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard shouldTrackSidebarDrag(value, pageWidth: pageWidth) else {
                    sidebarDragTranslation = 0
                    return
                }

                let baseOffset = isSidebarOpen ? 0 : -pageWidth
                let proposedOffset = clamped(baseOffset + value.translation.width, lower: -pageWidth, upper: 0)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    sidebarDragTranslation = proposedOffset - baseOffset
                }
            }
            .onEnded { value in
                guard shouldTrackSidebarDrag(value, pageWidth: pageWidth) else {
                    sidebarDragTranslation = 0
                    return
                }

                let baseOffset = isSidebarOpen ? 0 : -pageWidth
                let predictedOffset = clamped(baseOffset + value.predictedEndTranslation.width, lower: -pageWidth, upper: 0)
                let actualOffset = clamped(baseOffset + value.translation.width, lower: -pageWidth, upper: 0)
                let targetOffset = isSidebarOpen
                    ? min(predictedOffset, actualOffset)
                    : max(predictedOffset, actualOffset)

                withAnimation(.snappy(duration: 0.28)) {
                    isSidebarOpen = targetOffset > -pageWidth * 0.55
                    sidebarDragTranslation = 0
                }
            }
    }

    private func shouldTrackSidebarDrag(_ value: DragGesture.Value, pageWidth: CGFloat) -> Bool {
        let horizontalDistance = abs(value.translation.width)
        let verticalDistance = abs(value.translation.height)
        guard horizontalDistance > verticalDistance * 1.2 else { return false }

        if isSidebarOpen {
            return value.translation.width < 0
        } else {
            return value.startLocation.x <= 34
        }
    }

    private func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

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
        let recordingSignature = signature(for: url)

        if recordingSignature == activeRecordingSignature || recordingSignature == lastCompletedRecordingSignature {
            Logger.audio.warning("Skipping duplicate transcription request for the same recording.")
            return
        }

        activeRecordingSignature = recordingSignature

        Task {
            var shouldRememberSignature = false

            defer {
                Task { @MainActor in
                    if activeRecordingSignature == recordingSignature {
                        activeRecordingSignature = nil
                        if shouldRememberSignature {
                            lastCompletedRecordingSignature = recordingSignature
                        }
                    }
                }
            }

            var transcript = ""

            do {
                transcript = try await transcriberService.transcribe(audioURL: url)
                shouldRememberSignature = true
            } catch {
                Logger.transcription.error("Transcription error: \(error.localizedDescription)")
                await MainActor.run {
                    transcriptionError = error.localizedDescription
                }
            }

            await MainActor.run {
                guard let draft = draftManager.currentDraft else { return }
                var insertedText = ""

                if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    var newContent = draft.content

                    // Ensure we handle index correctly because Swift String indices are not integer offsets.
                    if cursorPosition > newContent.count {
                        cursorPosition = newContent.count
                    }
                    let index = newContent.index(newContent.startIndex, offsetBy: cursorPosition)

                    let textToInsert = (cursorPosition > 0 ? " " : "") + transcript

                    newContent.insert(contentsOf: textToInsert, at: index)
                    draftManager.updateCurrentDraft(content: newContent)

                    cursorPosition += textToInsert.count
                    insertedText = textToInsert
                } else {
                    Logger.transcription.info("Recording produced an empty transcription result.")
                }

                let recording = AudioRecordingStore.shared.makeRecordingMetadata(
                    for: url,
                    noteDate: draft.createdAt.journalDate,
                    transcriptText: insertedText.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                draftManager.attachRecording(recording, to: draft)
            }

            shouldRememberSignature = true
        }
    }

    private func signature(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = values?.fileSize ?? 0
        let modifiedAt = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(fileSize)|\(modifiedAt)"
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
                    draftManager.markRecordingsSubmitted(for: draft, noteDate: date)
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

    private func shareCurrentAudio() {
        guard let recordings = draftManager.currentDraft?.recordings, !recordings.isEmpty else {
            audioShareError = AudioRecordingStoreError.noRecordings.localizedDescription
            return
        }

        isExportingAudio = true

        Task {
            do {
                let url = try await AudioRecordingStore.shared.exportCombinedAudio(for: recordings)
                await MainActor.run {
                    shareSheetPayload = ShareSheetPayload(items: [url])
                    isExportingAudio = false
                }
            } catch {
                await MainActor.run {
                    audioShareError = error.localizedDescription
                    isExportingAudio = false
                }
            }
        }
    }

    private var audioShareErrorBinding: Binding<Bool> {
        Binding(
            get: { audioShareError != nil },
            set: { isPresented in
                if !isPresented {
                    audioShareError = nil
                }
            }
        )
    }

    private var transcriptionErrorBinding: Binding<Bool> {
        Binding(
            get: { transcriptionError != nil },
            set: { isPresented in
                if !isPresented {
                    transcriptionError = nil
                }
            }
        )
    }

    private func actionButton(
        title: String,
        systemImage: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled)
    }

    private func actionLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private struct ShareSheetPayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
