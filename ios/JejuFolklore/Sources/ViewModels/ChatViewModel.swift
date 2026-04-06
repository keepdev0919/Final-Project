import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isStreaming = false

    var courseId: String?

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        inputText = ""
        messages.append(ChatMessage(role: "user", content: text, sources: []))

        isStreaming = true
        var assistantContent = ""
        let assistantIndex = messages.count
        messages.append(ChatMessage(role: "assistant", content: "", sources: []))

        let recentHistory = Array(messages.dropLast().suffix(12))

        for await token in ChatAPI.stream(message: text, history: recentHistory, courseId: courseId) {
            assistantContent += token
            messages[assistantIndex] = ChatMessage(role: "assistant", content: assistantContent, sources: [])
        }

        isStreaming = false
    }
}
