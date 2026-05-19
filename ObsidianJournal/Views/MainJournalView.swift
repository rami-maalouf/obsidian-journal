import SwiftUI
import UniformTypeIdentifiers

// Mock because it is in Shared
// In real app, make sure AIResponse is available to both
// But LLMService is in Ignite/Services, so AIResponse is there.
// JournalService is in Shared. We need AIResponse in Shared or duplicate structure.
// NOTE: I will rely on JournalService using the structure defined in Shared if I move it there,
// OR I will define AIResponse in JournalService.swift to make it available globally.

// FIX: To ensure 'AIResponse' is visible to JournalService (in Shared),
// I should have defined AIResponse in JournalService.swift or a shared model file.
// For now, I will assume I need to move AIResponse to `Shared/JournalService.swift` or a new file.
// I will just redefine it in JournalService for now or use the one I just added if I can access it.

struct MainJournalView: View {
    @ObservedObject var vaultManager: VaultManager
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var transcriber = TranscriberService()
    @StateObject private var llmService = LLMService()
    @StateObject private var fileImportManager = FileImportManager()
    @State private var journalService: JournalService?

    @State private var transcriptionText: String = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // MARK: - Header
                VStack {
                    Text(Date(), style: .date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Daily Journal")
                        .font(.title)
                        .fontWeight(.bold)
                }

                Spacer()

                // MARK: - Visualization / Status
                if audioRecorder.isRecording {
                    VStack {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 120))
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse.byLayer)

                        Text("Recording...")
                            .font(.headline)
                            .foregroundStyle(.red)
                    }
                } else if isProcessing {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Processing with AI...")
                            .padding(.top)
                    }
                } else {
                    Button(action: {
                        audioRecorder.startRecording()
                    }) {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 120))
                            .foregroundStyle(ThemeManager.obsidianPurple)
                            .shadow(radius: 10)
                    }

                    // Import Button
                    Button(action: {
                        fileImportManager.startImport()
                    }) {
                        Label("Import File", systemImage: "arrow.down.doc")
                    }
                    .padding(.top)
                }

                Spacer()

                // MARK: - Controls
                if audioRecorder.isRecording {
                    Button(action: {
                        finishRecording()
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.primary)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .padding()
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "gear")
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset Vault") {
                        vaultManager.reset()
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(vaultManager)
            }
            .fileImporter(
                isPresented: $fileImportManager.isImporterPresented,
                allowedContentTypes: fileImportManager.allowedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                fileImportManager.handleImport(result: result) { finalResult in
                    switch finalResult {
                    case .success(let url):
                        processImportedFile(url: url)
                    case .failure(let error):
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .onAppear {
                self.journalService = JournalService(vaultManager: vaultManager)
            }
            .onReceive(audioRecorder.$recordingURL) { url in
                if let url, !audioRecorder.isRecording {
                    processRecording(url: url)
                }
            }
        }
    }

    func finishRecording() {
        audioRecorder.stopRecording()
    }

    func processRecording(url: URL) {
        processContent(audioURL: url)
    }

    func processImportedFile(url: URL) {
        // If audio
        if url.pathExtension.lowercased() == "m4a" || url.pathExtension.lowercased() == "mp3" {
            processContent(audioURL: url)
        } else {
            // Assume text
            do {
                let text = try String(contentsOf: url)
                processContent(text: text)
            } catch {
                errorMessage = "Failed to read text file"
            }
        }
    }

    func processContent(audioURL: URL? = nil, text: String? = nil) {
        isProcessing = true
        errorMessage = nil

        Task {
            do {
                var finalText = text ?? ""

                // 1. Transcribe if audio
                if let audioURL = audioURL {
                    finalText = try await transcriber.transcribe(audioURL: audioURL)
                    await MainActor.run { self.transcriptionText = finalText }
                }

                // 2. AI Processing
                let aiResponse = try await llmService.processJournalEntry(text: finalText)

                // 3. Save
                try await journalService?.saveAIEntry(originalText: finalText, aiResponse: aiResponse)

                await MainActor.run {
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Error: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }
}
