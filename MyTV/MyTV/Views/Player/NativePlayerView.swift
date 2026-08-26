import SwiftUI
import KSPlayer

public struct NativePlayerView: View {
    @ObservedObject private var playback = PlaybackManager.shared
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = playback.activePlayableURL {
                KSVideoPlayerView(
                    url: url,
                    options: playback.makeOptions(),
                    title: playback.currentMedia?.title
                )
                .ignoresSafeArea()
            }

            if let error = playback.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.yellow)

                    Text("Yayın Hatası")
                        .font(.headline.bold())
                        .foregroundStyle(.white)

                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    HStack(spacing: 12) {
                        Button("Yeniden Dene") {
                            playback.retry()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Kapat") {
                            playback.stop()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                }
                .padding(28)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding()
            }
        }
        #if os(iOS)
        .ignoresSafeArea()
        .statusBarHidden(true)
        #endif
        .onDisappear {
            Task { @MainActor in
                playback.stop()
            }
        }
    }
}
