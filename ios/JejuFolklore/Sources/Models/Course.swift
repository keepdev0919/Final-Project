import Foundation

struct Course: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let durationDays: Int
    let places: [CoursePlace]
    let estimatedMinutes: Int
    let sourceCourseId: String
    let narrative: String

    init(id: String, title: String, durationDays: Int, places: [CoursePlace],
         estimatedMinutes: Int, sourceCourseId: String = "", narrative: String = "") {
        self.id = id
        self.title = title
        self.durationDays = durationDays
        self.places = places
        self.estimatedMinutes = estimatedMinutes
        self.sourceCourseId = sourceCourseId
        self.narrative = narrative
    }
}

// 코스 리스트 화면용 경량 모델
struct CourseListItem: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let durationDays: Int
    let places: [CoursePlace]
}
