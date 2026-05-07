import SwiftUI

struct FolkloreDetailView: View {
    let pin: Pin
    @StateObject private var audio = AudioPlayer.shared
    @State private var detail: PinDetail?
    @State private var isLoadingDetail = false
    @State private var isLoadingTTS = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    Divider()
                    contentSection
                }
                .padding(20)
            }
            .navigationTitle(displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ttsButton
                }
            }
        }
        .task { await loadDetail() }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(detail?.sourceTypeLabel ?? pin.sourceTypeLabel,
                      systemImage: pin.sourceType == "legend" ? "book.fill" : "mic.fill")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(tagColor.opacity(0.15))
                    .foregroundColor(tagColor)
                    .clipShape(Capsule())

                if !pin.primaryPlace.isEmpty {
                    Label(pin.primaryPlace, systemImage: "mappin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(displayTitle)
                .font(.title2)
                .fontWeight(.bold)

            Text(detail?.summary ?? pin.summary)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        Group {
            if isLoadingDetail {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.top, 40)
            } else if let fullText = detail?.fullText, !fullText.isEmpty {
                Text(fullText)
                    .font(.body)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(pin.summary)
                    .font(.body)
                    .lineSpacing(7)
            }
        }
    }

    // MARK: - TTS Button

    private var ttsButton: some View {
        Button {
            if audio.isPlaying {
                audio.stop()
            } else {
                Task { await playTTS() }
            }
        } label: {
            Image(systemName: audio.isPlaying ? "speaker.wave.3.fill" : "play.circle.fill")
                .foregroundColor(tagColor)
        }
        .disabled(isLoadingTTS)
    }

    // MARK: - Helpers

    private var displayTitle: String { pin.displayTitle }

    private var tagColor: Color {
        pin.sourceType == "legend" ? .orange : .purple
    }

    private func loadDetail() async {
        isLoadingDetail = true
        detail = try? await PinDetailAPI.fetch(codeNo: pin.codeNo)
        isLoadingDetail = false
    }

    private func playTTS() async {
        let text = detail?.fullText ?? pin.summary
        isLoadingTTS = true
        do {
            let data = try await TTSAPI.fetch(text: String(text.prefix(500)), pinId: pin.id)
            audio.play(data: data)
        } catch {}
        isLoadingTTS = false
    }
}
