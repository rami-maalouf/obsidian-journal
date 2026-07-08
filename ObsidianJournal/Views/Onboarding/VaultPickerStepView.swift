import SwiftUI

// MARK: - Step 5: Vault Picker (Final Step)

struct VaultPickerStepView: View {
    var theme: AppTheme
    @ObservedObject var vaultManager: VaultManager

    @State private var showContent = false
    @State private var showPicker = false
    @State private var showButton = false
    @State private var isPickerPresented = false
    @State private var isInferringTemplate = false

    var body: some View {
        ZStack {
            theme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                // Header
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(theme.accent.opacity(0.2))
                            .frame(width: 80, height: 80)
                            .blur(radius: 20)

                        Image(systemName: "folder.fill.badge.plus")
                            .font(.system(size: 50))
                            .foregroundStyle(theme.accent)
                    }

                    Text("Connect Your Vault")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(theme.textPrimary)

                    Text("Select the folder where your daily notes live. This is usually your vault root or a 'Daily Notes' subfolder.")
                        .font(.body)
                        .foregroundColor(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)

                // Vault status card
                VStack(spacing: 16) {
                    if vaultManager.isVaultConfigured {
                        // Connected state
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(Color(hex: "#4CD964"))

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Vault Connected")
                                    .font(.headline)
                                    .foregroundColor(theme.textPrimary)

                                if let url = vaultManager.vaultURL {
                                    Text(url.lastPathComponent)
                                        .font(.subheadline)
                                        .foregroundColor(theme.textSecondary)
                                }
                            }

                            Spacer()

                            Button {
                                isPickerPresented = true
                            } label: {
                                Text("Change")
                                    .font(.subheadline)
                                    .foregroundColor(theme.accent)
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(theme.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color(hex: "#4CD964").opacity(0.3), lineWidth: 1)
                                )
                        )
                    } else {
                        // Not connected state
                        Button {
                            isPickerPresented = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 24))
                                    .foregroundColor(theme.accent)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Select Daily Notes Folder")
                                        .font(.headline)
                                        .foregroundColor(theme.textPrimary)

                                    Text("Tap to browse your files")
                                        .font(.subheadline)
                                        .foregroundColor(theme.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(theme.textSecondary)
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(theme.cardBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(theme.accent.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .opacity(showPicker ? 1 : 0)

                // Info text
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#4CD964"))

                        Text("Your files never leave your device")
                            .font(.caption)
                            .foregroundColor(theme.textSecondary)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#5AC8FA"))

                        Text("Works with iCloud Drive & local folders")
                            .font(.caption)
                            .foregroundColor(theme.textSecondary)
                    }
                }
                .opacity(showPicker ? 1 : 0)

                Spacer()

                // Complete button
                if vaultManager.isVaultConfigured {
                    Button {
                        completeOnboarding()
                    } label: {
                        Text("Start Journaling")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(theme.actionPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(30)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                    .opacity(showButton ? 1 : 0)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isPickerPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    vaultManager.setVaultFolder(url)
                    inferTemplateIfNeeded()
                    withAnimation(.spring()) {
                        showButton = true
                    }
                }
            case .failure(let error):
                print("Folder picker error: \(error)")
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                showContent = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                showPicker = true
            }
            if vaultManager.isVaultConfigured {
                withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                    showButton = true
                }
                inferTemplateIfNeeded()
            }
        }
    }

    private func inferTemplateIfNeeded() {
        guard vaultManager.inferredTemplate == nil else { return }
        guard let apiKey = KeychainManager.shared.getAPIKey(), !apiKey.isEmpty else { return }
        guard !isInferringTemplate else { return }

        isInferringTemplate = true

        Task {
            defer {
                Task { @MainActor in
                    isInferringTemplate = false
                }
            }

            do {
                let samples = try vaultManager.fetchRecentDailyNotes(count: 5)
                guard !samples.isEmpty else { return }

                let template = try await LLMService().inferTemplate(from: samples)
                await MainActor.run {
                    vaultManager.saveTemplate(template)
                }
            } catch {
                // best-effort during onboarding; user can re-run from Settings
            }
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        vaultManager.showOnboarding = false
        // Navigation will be handled by the parent view observing vaultManager state
    }
}

#Preview {
    NavigationStack {
        VaultPickerStepView(theme: ThemeManager.shared.currentTheme(for: .dark), vaultManager: VaultManager())
    }
}
