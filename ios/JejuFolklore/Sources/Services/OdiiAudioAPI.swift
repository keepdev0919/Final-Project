import Foundation

/// 오디 장소의 해설 음성.
///
/// 서버가 오디에서 대본을 실시간으로 받아 곱닥이 목소리(Typecast)로 읽어 준다.
/// 같은 대본이면 서버가 캐시를 주므로 두 번째부터는 즉시 온다 (설계 v2 §2 · 안 D).
///
/// ⚠️ **좌표를 보내지 않는다.** `stid`만 보낸다. 위치 판정은 단말에서만 한다.
enum OdiiAudioAPI {
    enum Emotion: String {
        case normal, whisper, happy
    }

    /// 스트리밍 재생용 URL. 3분짜리 음성을 통째로 내려받지 않고 흘려 듣는다.
    static func streamURL(stid: String, lang: String = "ko",
                          emotion: Emotion = .normal) -> URL? {
        var c = URLComponents(string: Config.baseURL + "/tts/odii")
        c?.queryItems = [
            .init(name: "stid", value: stid),
            .init(name: "lang", value: lang),
            .init(name: "emotion", value: emotion.rawValue),
        ]
        return c?.url
    }

    /// "미리 받아두기" — 통신이 불안한 곳(성산 정상 등)에서 쓰려고 미리 통째로 받는다.
    static func download(stid: String, lang: String = "ko",
                         emotion: Emotion = .normal) async throws -> Data {
        guard let url = streamURL(stid: stid, lang: lang, emotion: emotion) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
