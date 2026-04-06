import Foundation

struct ChatAPI {
    static func stream(
        message: String,
        history: [ChatMessage],
        courseId: String? = nil
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                guard let url = URL(string: Config.baseURL + "/chat") else {
                    continuation.finish()
                    return
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                let body = ChatRequest(message: message, history: history, courseId: courseId)
                request.httpBody = try? JSONEncoder().encode(body)

                guard let (bytes, _) = try? await URLSession.shared.bytes(for: request) else {
                    continuation.finish()
                    return
                }

                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))
                    if payload == "[DONE]" { break }
                    if let data = payload.data(using: .utf8),
                       let json = try? JSONDecoder().decode([String: String].self, from: data),
                       let text = json["text"] {
                        continuation.yield(text)
                    }
                }
                continuation.finish()
            }
        }
    }
}
