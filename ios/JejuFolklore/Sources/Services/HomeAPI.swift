import Foundation

/// 홈 화면 전용 API.
///
/// `/home/stages` — **스테이지 카드.** 홈이 부르는 유일한 것이다. 라벨(종류)마다 1등 하나씩,
/// 서버 `data/home_stage.json`이 정한다.
///
/// 안 부르는 것 둘:
/// - `/home/places` (순위 목록 121곳) — 지도·검색이 쓸 것이다
/// - `/home/recommendations` (추천 코스) — 홈에서 「오늘의 추천 코스」 섹션을 없앤
///   2026-08-24부터 앱이 부르지 않는다. 서버 쪽은 남겨 뒀다
///   (`tests/test_folklore_removed.py`가 iOS `Course` 디코딩 함정을 그 경로로 지킨다).
struct HomeStagesResponse: Codable {
    let stages: [HomeStage]
}

struct HomeAPI {
    static func stages() async throws -> [HomeStage] {
        let response: HomeStagesResponse =
            try await APIClient.shared.get("/home/stages", query: [:])
        return response.stages
    }
}
