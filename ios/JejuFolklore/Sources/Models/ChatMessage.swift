import Foundation

struct ChatMessage: Codable, Identifiable {
    let role: String    // "user" | "assistant"
    let content: String
    let sources: [String]

    var id: UUID = UUID()

    enum CodingKeys: String, CodingKey {
        case role, content, sources
    }
}

struct ChatRequest: Encodable {
    let message: String
    let history: [ChatMessage]
    let courseId: String?
}
