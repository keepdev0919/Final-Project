import SwiftUI

struct FolkloreDetailView: View {
    let pin: Pin
    @StateObject private var audio = AudioPlayer.shared
    @State private var selectedTab = 0
    @State private var isLoadingTTS = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("탭", selection: $selectedTab) {
                    Text("설화").tag(0)
                    Text("공식 안내").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(16)

                if selectedTab == 0 {
                    folkloreTab
                } else {
                    officialGuideTab
                }
            }
            .navigationTitle(pin.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var folkloreTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(pin.sourceTypeLabel, systemImage: pin.sourceType == "legend" ? "book.fill" : "mic.fill")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(pin.sourceType == "legend" ? Color.orange.opacity(0.15) : Color.purple.opacity(0.15))
                        .foregroundColor(pin.sourceType == "legend" ? .orange : .purple)
                        .clipShape(Capsule())
                    if !pin.primaryPlace.isEmpty {
                        Label(pin.primaryPlace, systemImage: "mappin")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Text(pin.summary)
                    .font(.body)
                    .lineSpacing(6)

                Button {
                    Task { await playTTS() }
                } label: {
                    Label(
                        audio.isPlaying ? "재생 중..." : (isLoadingTTS ? "로딩 중..." : "설화 듣기"),
                        systemImage: audio.isPlaying ? "speaker.wave.3.fill" : "play.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(audio.isPlaying || isLoadingTTS)
            }
            .padding(20)
        }
    }

    private var officialGuideTab: some View {
        VStack {
            Spacer()
            ContentUnavailableView(
                "공식 안내 없음",
                systemImage: "headphones",
                description: Text("이 장소의 공식 오디오 가이드가 없습니다")
            )
            Spacer()
        }
    }

    private func playTTS() async {
        isLoadingTTS = true
        do {
            let data = try await TTSAPI.fetch(text: pin.summary, pinId: pin.id)
            audio.play(data: data)
        } catch {
            // TTS 실패 시 조용히 무시 (텍스트로 폴백)
        }
        isLoadingTTS = false
    }
}
