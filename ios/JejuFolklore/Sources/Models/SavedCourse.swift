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

    // MARK: - Exploration archive fields (Optional for auto-migration)
    var journalText: String?
    var journalImageData: Data?
    var visitedPlaceNamesData: Data?   // JSON-encoded [String]
    var exploredAt: Date?

    init(from course: Course) {
        self.id = course.id
        self.title = course.title
        self.durationDays = course.durationDays
        self.estimatedMinutes = course.estimatedMinutes
        self.savedAt = Date()
        self.placesData = (try? JSONEncoder().encode(course.places)) ?? Data()
        self.journalText = nil
        self.journalImageData = nil
        self.visitedPlaceNamesData = nil
        self.exploredAt = nil
    }

    var places: [CoursePlace] {
        (try? JSONDecoder().decode([CoursePlace].self, from: placesData)) ?? []
    }

    /// 탐험 결과 디코딩 — 저장된 방문 장소 이름 리스트
    var visitedPlaceNames: [String]? {
        guard let data = visitedPlaceNamesData else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    /// 탐험이 완료되어 일지/이미지가 저장된 코스인지 여부
    var hasExploration: Bool {
        journalText != nil
    }

    /// 한 번에 탐험 결과를 기록
    func recordExploration(journalText: String, imageData: Data?, visitedPlaces: [String]) {
        self.journalText = journalText
        self.journalImageData = imageData
        self.visitedPlaceNamesData = (try? JSONEncoder().encode(visitedPlaces))
        self.exploredAt = Date()
    }
}
