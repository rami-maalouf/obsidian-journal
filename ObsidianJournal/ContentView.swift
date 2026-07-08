import SwiftUI

struct ContentView: View {
    @StateObject private var vaultManager = VaultManager()
    @EnvironmentObject private var transcriberService: TranscriberService

    var body: some View {
        ZStack {
            Group {
                if vaultManager.isVaultConfigured && !vaultManager.showOnboarding {
                    MainEditorView()
                        .environmentObject(vaultManager)
                        .environmentObject(JournalService(vaultManager: vaultManager))
                } else {
                    OnboardingView(vaultManager: vaultManager)
                }
            }

            // Transcription Loading Overlay
            if transcriberService.isTranscribing {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)

                    Text("Transcribing Audio...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(30)
                .background(Material.ultraThinMaterial)
                .cornerRadius(16)
                .shadow(radius: 10)
            }
        }
        .alert("Shared Audio Transcription Failed", isPresented: shareTranscriptionErrorBinding) {
            Button("OK", role: .cancel) {
                transcriberService.shareTranscriptionError = nil
            }
        } message: {
            Text(transcriberService.shareTranscriptionError ?? "")
        }
    }

    private var shareTranscriptionErrorBinding: Binding<Bool> {
        Binding(
            get: { transcriberService.shareTranscriptionError != nil },
            set: { isPresented in
                if !isPresented {
                    transcriberService.shareTranscriptionError = nil
                }
            }
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(TranscriberService())
}
