import SwiftUI
import Speech

struct PlaceReviewSheet: View {
    let placeName: String
    let companion: CompanionCharacter
    let onDone: () -> Void

    private static let tags: [(key: String, display: String)] = [
        ("소름 돋아요", "👻 소름 돋아요"),
        ("감동이에요",  "🥹 감동이에요"),
        ("신기해요",   "🤔 신기해요"),
        ("무서워요",   "😱 무서워요"),
        ("역사적이에요","📜 역사적이에요"),
    ]

    @EnvironmentObject private var authManager: AuthManager
    @State private var selectedKeys: Set<String> = []
    @State private var note: String = ""
    @State private var isSubmitting = false
    @StateObject private var speech = SpeechRecognizer()
    @State private var pulse = false
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(placeName)")
                    .font(.title3.weight(.semibold))
                Text("어떤 설화 경험이었나요?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Self.tags, id: \.key) { tag in
                        Button {
                            if selectedKeys.contains(tag.key) {
                                selectedKeys.remove(tag.key)
                            } else {
                                selectedKeys.insert(tag.key)
                            }
                        } label: {
                            Text(tag.display)
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(
                                    selectedKeys.contains(tag.key)
                                        ? companion.themeColor.opacity(0.15)
                                        : Color(.secondarySystemBackground)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            selectedKeys.contains(tag.key)
                                                ? companion.themeColor
                                                : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.primary)
                    }
                }

                // 메모 입력 영역: TextField + 마이크 버튼
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        TextField("한 줄 감상 남기기 (선택, 200자)", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onChange(of: note) {
                                if note.count > 200 { note = String(note.prefix(200)) }
                            }

                        micButton
                            .padding(.top, 2)
                    }

                    if let err = speech.lastErrorMessage {
                        Text(err)
                            .font(.caption2)
                            .foregroundColor(.red)
                    } else if !speech.canRecord && speech.authorizationStatus != .notDetermined {
                        Text("마이크 권한이 필요해요")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if speech.isRecording {
                        Text("듣고 있어요…")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
                // 음성 인식 결과를 note에 반영(이어 붙이기)
                .onChange(of: speech.transcript) { _, newValue in
                    // 200자 제한 유지
                    note = String(newValue.prefix(200))
                }

                Spacer()

                HStack(spacing: 12) {
                    Button("건너뛰기") { onDone() }
                        .buttonStyle(.bordered)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)

                    Button(isSubmitting ? "저장 중..." : "남기기 →") {
                        Task { await submit() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(companion.themeColor)
                    .disabled(selectedKeys.isEmpty || isSubmitting)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showLogin) {
            LoginSheet()
        }
        .task {
            // TTS가 점유한 .playback AVAudioSession을 해제해야 마이크 캡처(.playAndRecord)가 가능.
            // 이 호출 없이는 input node가 invalid format(sampleRate=0)을 반환해 "마이크 초기화 실패" 에러가 뜸.
            AudioPlayer.shared.stop()
            // 시트 진입 시 권한 상태 확인 + 미결정이면 한 번 요청
            if speech.authorizationStatus == .notDetermined || speech.microphonePermission == .undetermined {
                await speech.requestPermissions()
            }
        }
        .onDisappear {
            speech.stop()
        }
    }

    // MARK: - Mic button

    @ViewBuilder
    private var micButton: some View {
        Button {
            handleMicTap()
        } label: {
            ZStack {
                // 녹음 중일 때 빨간 펄스 배경
                if speech.isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.25))
                        .frame(width: 48, height: 48)
                        .scaleEffect(pulse ? 1.2 : 0.9)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                }

                Circle()
                    .fill(speech.isRecording ? Color.red : companion.themeColor)
                    .frame(width: 44, height: 44)

                Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .disabled(!speech.canRecord && speech.authorizationStatus != .notDetermined)
        .opacity((speech.canRecord || speech.authorizationStatus == .notDetermined) ? 1.0 : 0.4)
        .accessibilityLabel(speech.isRecording ? "받아쓰기 중지" : "받아쓰기 시작")
    }

    private func handleMicTap() {
        if speech.isRecording {
            speech.stop()
            pulse = false
        } else {
            // 권한이 아직 안 결정됐으면 먼저 요청
            if speech.authorizationStatus == .notDetermined || speech.microphonePermission == .undetermined {
                Task {
                    await speech.requestPermissions()
                    if speech.canRecord {
                        // 현재 키보드 입력 텍스트를 transcript에 동기화한 뒤 시작 → 이어 붙이기
                        speech.transcript = note
                        speech.start()
                        pulse = speech.isRecording
                    }
                }
            } else if speech.canRecord {
                speech.transcript = note
                speech.start()
                pulse = speech.isRecording
            }
        }
    }

    private func submit() async {
        guard authManager.isLoggedIn else {
            showLogin = true
            return
        }
        isSubmitting = true
        await APIClient.shared.submitReview(
            placeName: placeName,
            tags: Array(selectedKeys),
            note: note.isEmpty ? nil : note
        )
        isSubmitting = false
        onDone()
    }
}
