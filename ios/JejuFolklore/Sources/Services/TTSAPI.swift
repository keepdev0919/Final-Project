import Foundation

private struct TTSRequest: Encodable {
    let text: String
    let voice: String
}

/// TTS 결과 in-memory 캐시 (반복 시연 시 즉시 재생용).
/// cacheKey가 nil이면 캐시 사용 안 함.
private final class TTSCache {
    static let shared = TTSCache()
    private let cache = NSCache<NSString, NSData>()
    private init() {
        cache.countLimit = 64
    }

    func get(_ key: String) -> Data? {
        cache.object(forKey: key as NSString) as Data?
    }

    func set(_ key: String, data: Data) {
        cache.setObject(data as NSData, forKey: key as NSString)
    }
}

struct TTSAPI {
    /// 페르소나 voice + 선택적 캐싱 키.
    /// - Parameters:
    ///   - text: 합성할 텍스트
    ///   - voice: OpenAI tts-1 voice (alloy/echo/fable/nova/onyx/shimmer)
    ///   - cacheKey: nil이면 캐시 미사용. 정적 텍스트(인사말 등)는 키 지정 권장.
    static func fetch(text: String, voice: String, cacheKey: String?) async throws -> Data {
        if let key = cacheKey, let cached = TTSCache.shared.get(key) {
            return cached
        }
        let data = try await APIClient.shared.postData(
            "/tts",
            body: TTSRequest(text: text, voice: voice)
        )
        if let key = cacheKey {
            TTSCache.shared.set(key, data: data)
        }
        return data
    }
}
