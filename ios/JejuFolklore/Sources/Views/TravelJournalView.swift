// ios/JejuFolklore/Sources/Views/TravelJournalView.swift
import SwiftUI

struct TravelJournalView: View {
    let journalText: String
    let visitedPlaces: [String]
    let companion: CompanionCharacter
    let onDone: () -> Void

    @State private var showShareSheet = false
    @State private var isPreparingTTS = false
    @State private var ttsTask: Task<Void, Never>?
    @StateObject private var audio = AudioPlayer.shared

    private var shareText: String {
        """
        제주 설화 여행 일지

        \(companion.emoji) \(companion.displayName)와 함께한 제주 여행
        방문: \(visitedPlaces.joined(separator: ", "))

        \(journalText)
        """
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(companion.emoji) \(companion.displayName)와 함께한 여행")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.orange)

                        Text("나의 제주 여행 일지")
                            .font(.title2.weight(.bold))

                        Text("방문: \(visitedPlaces.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Divider()
                        .padding(.horizontal, 20)

                    Text(journalText)
                        .font(.body)
                        .lineSpacing(6)
                        .padding(.horizontal, 20)

                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("여행 일지")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        journalTTSButton
                        Button("완료", action: onDone)
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(text: shareText)
            }
        }
        .onDisappear {
            ttsTask?.cancel()
            AudioPlayer.shared.stop()
        }
    }

    @ViewBuilder
    private var journalTTSButton: some View {
        if isPreparingTTS {
            ProgressView()
                .controlSize(.small)
        } else if audio.isPlaying {
            Button {
                ttsTask?.cancel()
                AudioPlayer.shared.stop()
            } label: {
                Image(systemName: "pause.circle.fill")
                    .font(.title3)
            }
            .accessibilityLabel("낭독 멈추기")
        } else {
            Button {
                playJournal()
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
            }
            .accessibilityLabel("일지 낭독하기")
        }
    }

    private func playJournal() {
        let text = journalText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isPreparingTTS = true
        ttsTask = Task {
            // 페르소나 무관 내레이터 voice (nova). 일지는 1인칭 회고이므로 통일.
            await TTSPlayerService.shared.speak(text: text, voice: "nova", cacheKey: nil)
            isPreparingTTS = false
        }
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Loading state

struct JournalLoadingView: View {
    let companion: CompanionCharacter

    var body: some View {
        VStack(spacing: 20) {
            Text(companion.emoji)
                .font(.system(size: 56))
            ProgressView()
                .scaleEffect(1.3)
            Text("\(companion.displayName)이(가) 여행을 정리하고 있어요...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
