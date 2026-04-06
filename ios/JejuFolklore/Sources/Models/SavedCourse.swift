import Foundation
import SwiftData

@Model
final class SavedCourse {
    var id: String
    var title: String
    var durationDays: Int
    var estimatedMinutes: Int
    var savedAt: Date
    var placesData: Data   // JSON-encoded [CoursePlace]

    init(from course: Course) {
        self.id = course.id
        self.title = course.title
        self.durationDays = course.durationDays
        self.estimatedMinutes = course.estimatedMinutes
        self.savedAt = Date()
        self.placesData = (try? JSONEncoder().encode(course.places)) ?? Data()
    }

    var places: [CoursePlace] {
        (try? JSONDecoder().decode([CoursePlace].self, from: placesData)) ?? []
    }
}
