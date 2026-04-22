import Foundation

// 레거시 — /course/recommend 호환 유지
struct CourseRequest: Encodable {
    let theme: String
    let categoryScores: [String: Int]?
    let durationDays: Int
}

struct CourseListRequest: Encodable {
    let region: String
    let categoryScores: [String: Int]
    let durationDays: Int
}

struct CourseDetailRequest: Encodable {
    let courseId: String
    let categoryScores: [String: Int]
}

struct CourseAPI {
    static func recommend(
        theme: String,
        categoryScores: [String: Int]? = nil,
        durationDays: Int
    ) async throws -> Course {
        try await APIClient.shared.post("/course/recommend", body: CourseRequest(
            theme: theme,
            categoryScores: categoryScores,
            durationDays: durationDays
        ))
    }

    static func list(
        region: String,
        categoryScores: [String: Int],
        durationDays: Int
    ) async throws -> [CourseListItem] {
        try await APIClient.shared.post("/course/list", body: CourseListRequest(
            region: region,
            categoryScores: categoryScores,
            durationDays: durationDays
        ))
    }

    static func detail(courseId: String, categoryScores: [String: Int]) async throws -> Course {
        try await APIClient.shared.post("/course/detail", body: CourseDetailRequest(
            courseId: courseId,
            categoryScores: categoryScores
        ))
    }
}
