import Foundation
import SwiftUI

/// TTS 재생 서비스.
///
/// ⚠️ **현재 호출부가 없다.** 유일한 사용처였던 도착 시 페르소나 인사말 재생을
/// 2026-08-13에 제거했다(설화 채팅·일지도 함께 제거). **지우지 말 것** —
/// 단계 1의 이야기 오디오 재생에 재사용한다. 캐시 기능이 특히 유용하다.
///
/// - mute 상태는 UserDefaults `companion_tts_muted` 키에 저장.
/// - speak 호출 시 이전 음성을 즉시 중단하고 새 음성으로 교체.
/// - TTS 실패 시 무음 폴백 (사용자 알림 없음).
@MainActor
final class TTSPlayerService: ObservableObject {
    static let shared = TTSPlayerService()

    @AppStorage("companion_tts_muted") var isMuted: Bool = false

    private init() {}

    /// 텍스트를 지정 voice로 합성해 즉시 재생.
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
