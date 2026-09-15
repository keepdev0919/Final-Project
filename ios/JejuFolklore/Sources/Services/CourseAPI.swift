import Foundation

// 설화 취향 점수(category_scores)는 2026-08-13에 전송을 중단했다.
// 코스 추천에서 설화를 분리해 서버가 무시하기 때문이다.
// 서버 스키마에는 선택 필드로 남아 있다(구 클라이언트 호환).

struct CourseListRequest: Encodable {
    let region: String
    let durationDays: Int
}

struct CourseDetailRequest: Encodable {
    let courseId: String
}

struct CourseAPI {
    static func list(
        region: String,
        durationDays: Int
    ) async throws -> [CourseListItem] {
        try await APIClient.shared.post("/course/list", body: CourseListRequest(
            region: region,
            durationDays: durationDays
        ))
    }

    /// 코스 탭 첫 화면에서 그냥 둘러보라고 깔아 두는 목록.
    /// 권역·기간을 보내지 않는다. **부를 때마다 서버가 다른 코스를 준다** —
    /// 새로고침이 곧 갱신이다.
    static func featured(limit: Int = 5) async throws -> [CourseListItem] {
        try await APIClient.shared.get("/course/featured", query: ["limit": "\(limit)"])
    }

    static func detail(courseId: String) async throws -> Course {
        try await APIClient.shared.post("/course/detail", body: CourseDetailRequest(
            courseId: courseId
        ))
    }
}
