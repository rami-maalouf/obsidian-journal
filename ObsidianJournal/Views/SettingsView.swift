import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @StateObject private var llmService = LLMService()
    @ObservedObject private var transcriptionSettings = TranscriptionSettings.shared
    @StateObject private var transcriberService = TranscriberService()
    @State private var apiKey: String = ""
    @State private var isReInferring = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                // MARK: - AI Configuration
                Section(header: Text("AI Configuration")) {
                    SecureField("OpenAI API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Text("Your API key is stored securely on device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: - Transcription Model
                Section(header: Text("Transcription Model")) {
                    Picker("Model", selection: $transcriptionSettings.selectedModel) {
                        ForEach(TranscriptionModel.allCases) { model in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(model.displayName)
                                        if model.isCloud {
                                            Image(systemName: "cloud.fill")
                                                .foregroundStyle(ThemeManager.obsidianPurple)
                                                .font(.caption)
                                        }
                                    }
                                    Text("\(model.sizeDescription) • \(model.accuracyDescription)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .tag(model)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    // Model status
                    if transcriptionSettings.selectedModel.isCloud {
                        if apiKey.isEmpty {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Cloud transcription requires an API key")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Ready for cloud transcription")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        // Local model status
                        switch transcriberService.modelLoadingState {
                        case .notLoaded:
                            HStack {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundStyle(ThemeManager.obsidianPurple)
                                Text("Model will download on first use")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        case .loading, .downloading:
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading model...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        case .loaded:
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Model ready")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        case .error(let message):
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        // Download progress if downloading
                        if transcriberService.isDownloading {
                            ProgressView(value: transcriberService.downloadProgress)
                                .progressViewStyle(.linear)
                        }
                    }
                }

                // MARK: - Template Status
                Section(header: Text("Daily Note Template")) {
                    if let template = vaultManager.inferredTemplate {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text("Template Learned")
                                    .font(.subheadline)
                                Text("Confidence: \(Int(template.confidence * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let notes = template.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("Variables: \(template.variables.map { $0.name }.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.orange)
                            Text("No template learned yet")
                                .font(.subheadline)
                        }
                    }

                    Button(action: reInferTemplate) {
                        HStack {
                            if isReInferring {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isReInferring ? "Analyzing..." : "Re-analyze Templates")
                        }
                    }
                    .disabled(isReInferring)
                }

                // MARK: - Actions
                Section {
                    Button("Save Key") {
                        KeychainManager.shared.saveAPIKey(apiKey)
                        dismiss()
                    }
                    .disabled(apiKey.isEmpty)
                }

                // MARK: - Vault
                Section(header: Text("Vault")) {
                    if let url = vaultManager.vaultURL {
                        Text(url.lastPathComponent)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Button("Reset Vault", role: .destructive) {
                        vaultManager.reset()
                        vaultManager.clearTemplate()
                        dismiss()
                    }
                }

                // MARK: - Development
                Section(header: Text("Development")) {
                    Button("Redo Onboarding") {
                        vaultManager.showOnboarding = true
                        dismiss()
                    }

                    Text("Re-experience the onboarding flow without losing any data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let key = KeychainManager.shared.getAPIKey() {
                    apiKey = key
                }
            }
        }
    }

    private func reInferTemplate() {
        isReInferring = true

        Task {
            do {
                let samples = try vaultManager.fetchRecentDailyNotes(count: 5)

                if !samples.isEmpty {
                    let template = try await llmService.inferTemplate(from: samples)
                    await MainActor.run {
                        vaultManager.saveTemplate(template)
                    }
                }
            } catch {
                // Error is logged by LLMService
            }

            await MainActor.run {
                isReInferring = false
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(VaultManager())
}
