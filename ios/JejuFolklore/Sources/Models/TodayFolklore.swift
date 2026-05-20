import Foundation

/// 홈 상단 "오늘의 설화" 카드용 모델
/// 백엔드 `/home/today` 응답과 매핑된다.
struct TodayFolklore: Codable, Identifiable, Equatable {
    let codeNo: String
    let title: String
    let hook: String
    let heroImage: String?
    let primaryPlace: String
    let lat: Double
    let lng: Double

    var id: String { codeNo }

    /// "C_M_001 각시당본풀이" → "각시당본풀이"
    var displayTitle: String {
        if let space = title.firstIndex(of: " ") {
            let after = title[title.index(after: space)...]
            if !after.isEmpty { return String(after) }
        }
        return title
    }
}

/// 추천 코스 응답 래퍼 (`/home/recommendations`)
struct HomeRecommendationsResponse: Codable {
    let courses: [Course]
}
