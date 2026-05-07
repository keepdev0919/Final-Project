import Foundation

// MARK: - CompanionCharacter

enum CompanionCharacter: String, Codable, CaseIterable {
    case hallam   = "마을 할망"
    case dang     = "당신·심방"
    case haenyeo  = "영등신·해녀 선배"
    case dokkaebi = "도깨비"
    case dochebi  = "도체비"

    var displayName: String { rawValue }

    var emoji: String {
        switch self {
        case .hallam:   return "👵"
        case .dang:     return "🪬"
        case .haenyeo:  return "🤿"
        case .dokkaebi: return "👺"
        case .dochebi:  return "👻"
        }
    }

    var greeting: String {
        switch self {
        case .hallam:   return "아이고, 어서 오라게."
        case .dang:     return "이 땅에 발을 들였도다."
        case .haenyeo:  return "왔어? 여기 처음이야?"
        case .dokkaebi: return "크크크, 왔네?"
        case .dochebi:  return "왔어요? 아니... 왔나?"
        }
    }

    static func from(categoryScores: [String: Int]) -> CompanionCharacter {
        let categoryMap: [String: CompanionCharacter] = [
            "무속신화·신격 전승": .dang,
            "생활민담·교훈담":   .dokkaebi,
            "마을 공동체 전승":  .hallam,
            "해양·어촌 전승":    .haenyeo,
            "초자연 존재담":     .dochebi,
        ]
        let best = categoryScores.max { $0.value < $1.value }
        return best.flatMap { categoryMap[$0.key] } ?? .hallam
    }
}

// MARK: - MessageRole

enum MessageRole: String, Codable {
    case user
    case assistant
}

// MARK: - TravelChatMessage

struct TravelChatMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    init(role: MessageRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

// MARK: - PlaceChatLog

struct PlaceChatLog: Codable, Identifiable {
    var id: String { placeName }
    let placeName: String
    var messages: [TravelChatMessage]
}

// MARK: - TravelSession

struct TravelSession: Codable {
    let courseId: String
    let companion: CompanionCharacter
    let startedAt: Date
    var visitedPlaceNames: [String]
    private(set) var chatLogs: [PlaceChatLog]
    let courseSnapshot: Course      // 앱 종료 후 복원용
    var transport: String

    init(courseId: String, companion: CompanionCharacter, course: Course, transport: String) {
        self.courseId = courseId
        self.companion = companion
        self.startedAt = Date()
        self.visitedPlaceNames = []
        self.chatLogs = []
        self.courseSnapshot = course
        self.transport = transport
    }

    mutating func appendMessage(_ msg: TravelChatMessage, to placeName: String) {
        if let idx = chatLogs.firstIndex(where: { $0.placeName == placeName }) {
            chatLogs[idx].messages.append(msg)
        } else {
            chatLogs.append(PlaceChatLog(placeName: placeName, messages: [msg]))
        }
    }
}

// MARK: - TravelStore (UserDefaults persistence)

@MainActor
final class TravelStore {
    static let shared = TravelStore()
    private let key = "active_travel_session"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private init() {}

    func save(_ session: TravelSession) {
        do {
            let data = try encoder.encode(session)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            assertionFailure("TravelSession encode failed: \(error)")
        }
    }

    func load() -> TravelSession? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let session = try? decoder.decode(TravelSession.self, from: data) else {
            return nil
        }
        return session
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
