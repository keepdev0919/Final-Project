import Foundation
import SwiftUI

/// 동행자 채팅 / 도착 오버레이 / 일지 등에서 공용으로 사용하는 TTS 재생 서비스.
/// - mute 상태는 UserDefaults `companion_tts_muted` 키에 저장.
/// - speak 호출 시 이전 음성을 즉시 중단하고 새 음성으로 교체.
/// - TTS 실패 시 무음 폴백 (사용자 알림 없음).
@MainActor
final class TTSPlayerService: ObservableObject {
    static let shared = TTSPlayerService()

    @AppStorage("companion_tts_muted") var isMuted: Bool = false

    private init() {}

    /// 텍스트를 페르소나 voice로 합성해 즉시 재생.
    /// - Parameters:
    ///   - text: 읽을 텍스트
    ///   - voice: OpenAI tts-1 voice
    ///   - cacheKey: 정적 텍스트(인사말 등)는 키 지정 시 반복 재생 즉시화
    func speak(text: String, voice: String, cacheKey: String? = nil) async {
        guard !isMuted else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        AudioPlayer.shared.stop()  // 이전 음성 즉시 중단
        do {
            let data = try await TTSAPI.fetch(text: trimmed, voice: voice, cacheKey: cacheKey)
            // 호출 후 mute로 전환됐다면 재생 스킵
            guard !isMuted else { return }
            AudioPlayer.shared.play(data: data)
        } catch {
            // 무음 폴백 — 채팅 텍스트는 정상 표시되므로 사용자 알림 불필요
        }
    }

    /// 재생 즉시 중단 (화면 dismiss 등).
    func stop() {
        AudioPlayer.shared.stop()
    }

    /// 토글 편의 메서드. mute 전환 시 현재 재생도 중단.
    func toggleMute() {
        isMuted.toggle()
        if isMuted {
            stop()
        }
    }
}
