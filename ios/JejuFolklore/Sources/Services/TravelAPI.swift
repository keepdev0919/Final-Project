import Foundation

struct CompanionChatRequest: Encodable {
    let placeName: String
    let folkloreSummaries: [String]
    let companionType: String
    let message: String
    let history: [CompanionHistoryItem]
}

struct CompanionHistoryItem: Encodable {
    let role: String
    let content: String
}

struct JournalRequestBody: Encodable {
    let visitedPlaces: [String]
    let chatLogs: [JournalChatLog]
}

struct JournalChatLog: Encodable {
    let placeName: String
    let messages: [CompanionHistoryItem]
}

struct JournalResponse: Decodable {
    let journalText: String
}

enum TravelAPI {
    static func companionStream(
        placeName: String,
        folkloreSummaries: [String],
        companionType: String,
        message: String,
        history: [TravelChatMessage]
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                guard let url = URL(string: Config.baseURL + "/travel/companion") else {
                    continuation.finish()
                    return
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                let historyItems = history.map { CompanionHistoryItem(role: $0.role.rawValue, content: $0.content) }
                let body = CompanionChatRequest(
                    placeName: placeName,
                    folkloreSummaries: folkloreSummaries,
                    companionType: companionType,
                    message: message,
                    history: historyItems
                )
                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                guard let httpBody = try? encoder.encode(body) else {
                    continuation.finish()
                    return
                }
                request.httpBody = httpBody

                guard let (bytes, _) = try? await URLSession.shared.bytes(for: request) else {
                    continuation.finish()
                    return
                }

                let jsonDecoder = JSONDecoder()
                do {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        if let data = payload.data(using: .utf8),
                           let json = try? jsonDecoder.decode([String: String].self, from: data),
                           let text = json["text"] {
                            continuation.yield(text)
                        }
                    }
                } catch {
                    // network error — stream ends cleanly
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func generateJournal(session: TravelSession) async throws -> String {
        let logs = session.chatLogs.map { log in
            JournalChatLog(
                placeName: log.placeName,
                messages: log.messages.map { CompanionHistoryItem(role: $0.role.rawValue, content: $0.content) }
            )
        }
        let body = JournalRequestBody(
            visitedPlaces: session.visitedPlaceNames,
            chatLogs: logs
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let url = URL(string: Config.baseURL + "/travel/journal") else {
            throw APIError.invalidURL
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(JournalResponse.self, from: data)
        return result.journalText
    }
}
