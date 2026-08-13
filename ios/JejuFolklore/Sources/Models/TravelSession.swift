import Foundation
import SwiftUI

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
    let startedAt: Date
    var visitedPlaceNames: [String]
    private(set) var chatLogs: [PlaceChatLog]
    let courseSnapshot: Course      // 앱 종료 후 복원용
    var transport: String

    init(courseId: String, course: Course, transport: String) {
        self.courseId = courseId
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
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        guard let session = try? decoder.decode(TravelSession.self, from: data) else {
            // 저장 형식이 바뀌어 못 읽는 데이터는 버린다.
            // 2026-08-13에 companion(5종 페르소나) 필드를 제거해 기존 세션이
            // 디코딩 실패한다. 남겨두면 매번 실패를 반복한다.
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        return session
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// 탐험(여행 일지) 완료 시 발송되는 글로벌 이벤트.
    /// ExploreView → 부모 view(CoursePreviewView, SavedCourseDetailView, ContentView 등)가
    /// 자신을 dismiss하여 TabView root까지 연쇄적으로 복귀하기 위한 신호.
    static let exploreDidComplete = Notification.Name("exploreDidComplete")
}
