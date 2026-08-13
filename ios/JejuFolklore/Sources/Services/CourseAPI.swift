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

    static func detail(courseId: String) async throws -> Course {
        try await APIClient.shared.post("/course/detail", body: CourseDetailRequest(
            courseId: courseId
        ))
    }
}
