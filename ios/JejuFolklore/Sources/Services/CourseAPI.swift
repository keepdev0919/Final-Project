import Foundation

struct CourseRequest: Encodable {
    let theme: String
    let durationDays: Int
    let transport: String
}

struct CourseAPI {
    static func recommend(theme: String, durationDays: Int, transport: String) async throws -> Course {
        try await APIClient.shared.post("/course/recommend", body: CourseRequest(
            theme: theme,
            durationDays: durationDays,
            transport: transport
        ))
    }
}
