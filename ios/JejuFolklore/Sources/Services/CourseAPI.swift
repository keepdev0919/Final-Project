import Foundation

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
