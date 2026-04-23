import Foundation

// MARK: - CompanionCharacter

enum CompanionCharacter: String, Codable, CaseIterable {
    case mudang = "당신/심방"
    case dokkaebi = "도깨비"
    case hallam = "마을 할망"
    case yeondeung = "영등신/해녀 선배"
    case dochevi = "도체비"

    var displayName: String { rawValue }

    var emoji: String {
        switch self {
        case .mudang:    return "🪷"
        case .dokkaebi:  return "👺"
        case .hallam:    return "👵"
        case .yeondeung: return "🌊"
        case .dochevi:   return "👻"
        }
    }

    var greeting: String {
        switch self {
        case .mudang:    return "당신이 오기를 기다렸습니다."
        case .dokkaebi:  return "어이쿠, 손님이 왔구만!"
        case .hallam:    return "아이고, 어서 오라게."
        case .yeondeung: return "바다 바람이 불어왔구나."
        case .dochevi:   return "...왔군."
        }
    }

    static func from(categoryScores: [String: Int]) -> CompanionCharacter {
        let top = categoryScores.max(by: { $0.value < $1.value })?.key ?? ""
        switch top {
        case "무속신화·신격 전승": return .mudang
        case "생활민담·교훈담":   return .dokkaebi
        case "마을 공동체 전승":  return .hallam
        case "해양·어촌 전승":    return .yeondeung
        case "초자연 존재담":     return .dochevi
        default:                 return .dokkaebi
        }
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

    init(courseId: String, companion: CompanionCharacter) {
        self.courseId = courseId
        self.companion = companion
        self.startedAt = Date()
        self.visitedPlaceNames = []
        self.chatLogs = []
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
