import Foundation

/// 홈 화면 전용 API.
/// - `/home/recommendations`: 추천 코스 목록 (기존 Course 모델 재사용)
///
/// `/home/today`(오늘의 설화)는 2026-08-14에 제거했다. 홈 최상단 자리는
/// 성산 여정 카드가 가져갔다.
/// 추천 코스 응답 래퍼 (`/home/recommendations`)
struct HomeRecommendationsResponse: Codable {
    let courses: [Course]
}

struct HomeAPI {
    static func recommendations() async throws -> [Course] {
        let response: HomeRecommendationsResponse =
            try await APIClient.shared.get("/home/recommendations", query: [:])
        return response.courses
    }
}
