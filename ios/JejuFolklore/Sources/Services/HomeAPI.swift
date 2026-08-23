import Foundation

/// 홈 화면 전용 API.
///
/// - `/home/stages`: **스테이지 카드 6곳.** 홈의 주인공이다. 라벨(종류)마다 1등 하나씩,
///   서버 `data/home_stage.json`이 정한다.
/// - `/home/recommendations`: 추천 코스 3선. 코스 탭으로 들어가는 곁길.
///
/// `/home/places`(순위 목록 121곳)는 지도·검색이 쓸 것이라 여기서 부르지 않는다.
struct HomeStagesResponse: Codable {
    let stages: [HomeStage]
}

/// 추천 코스 응답 래퍼 (`/home/recommendations`)
struct HomeRecommendationsResponse: Codable {
    let courses: [Course]
}

struct HomeAPI {
    static func stages() async throws -> [HomeStage] {
        let response: HomeStagesResponse =
            try await APIClient.shared.get("/home/stages", query: [:])
        return response.stages
    }

    static func recommendations() async throws -> [Course] {
        let response: HomeRecommendationsResponse =
            try await APIClient.shared.get("/home/recommendations", query: [:])
        return response.courses
    }
}
