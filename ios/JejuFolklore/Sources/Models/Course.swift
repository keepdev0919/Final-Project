import Foundation

struct Course: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let durationDays: Int
    let places: [CoursePlace]
    let estimatedMinutes: Int
}
