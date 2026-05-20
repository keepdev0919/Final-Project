import Foundation

/// 홈 화면 전용 API.
/// - `/home/today`: 오늘의 설화 한 건
/// - `/home/recommendations`: 추천 코스 목록 (기존 Course 모델 재사용)
struct HomeAPI {
    static func today() async throws -> TodayFolklore {
        try await APIClient.shared.get("/home/today", query: [:])
    }

    static func recommendations() async throws -> [Course] {
        let response: HomeRecommendationsResponse =
            try await APIClient.shared.get("/home/recommendations", query: [:])
        return response.courses
    }
}
