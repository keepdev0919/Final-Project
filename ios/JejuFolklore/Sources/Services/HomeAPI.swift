import Foundation

/// 홈 화면 전용 API.
///
/// - `/home/places`: **장소 카드 10곳.** 홈의 주인공이다. 실제 여행자가 많이 담은
///   순서로 뽑되 오디 해설이 있는 곳만 온다.
/// - `/home/recommendations`: 추천 코스 3선. 코스 탭으로 들어가는 곁길.
struct HomePlacesResponse: Codable {
    let places: [HomePlace]
}

/// 추천 코스 응답 래퍼 (`/home/recommendations`)
struct HomeRecommendationsResponse: Codable {
    let courses: [Course]
}

struct HomeAPI {
    static func places(limit: Int = 10) async throws -> [HomePlace] {
        let response: HomePlacesResponse =
            try await APIClient.shared.get("/home/places", query: ["limit": String(limit)])
        return response.places
    }

    static func recommendations() async throws -> [Course] {
        let response: HomeRecommendationsResponse =
            try await APIClient.shared.get("/home/recommendations", query: [:])
        return response.courses
    }
}
