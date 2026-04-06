import Foundation

private struct TTSRequest: Encodable {
    let text: String
    let pinId: String
}

struct TTSAPI {
    static func fetch(text: String, pinId: String) async throws -> Data {
        try await APIClient.shared.postData("/tts", body: TTSRequest(text: text, pinId: pinId))
    }
}
