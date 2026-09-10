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

    /// **코스의 진짜 신원.** `id` 는 서버가 상세를 줄 때마다 새로 만드는 UUID라
    /// (`/course/detail` 이 `id=uuid4()`, 진짜 id 를 `source_course_id` 로 준다)
    /// 같은 코스를 두 번 열면 서로 다른 값이 된다. 그래서 「이미 담았나」를
    /// `id` 로 물으면 **영원히 아니오**다 — 같은 코스가 목록에 계속 쌓였다.
    ///
    /// 옵셔널인 것은 이 필드가 생기기 전에 담아 둔 코스가 이미 있기 때문이다
    /// (2026-09-09). 값이 없으면 예전처럼 `id` 로 비교한다.
    var sourceCourseId: String?

    /// 중복 판정에 쓰는 키. 진짜 코스 id 가 있으면 그것을, 없으면 `id` 를 쓴다.
    var identityKey: String {
        if let s = sourceCourseId, !s.isEmpty { return s }
        return id
    }

    // MARK: - Exploration archive fields (Optional for auto-migration)
    // ⚠️ 일지·민화 생성은 2026-08-13에 제거했다. 아래 세 필드는 **기존 Firestore
    // 문서를 읽기 위해서만** 남긴다. 새로 값이 채워지는 경로는 없다.
    var journalText: String?
    var journalImageData: Data?
    var journalImageUrl: String?
    var visitedPlaceNamesData: Data?   // JSON-encoded [String]
    var exploredAt: Date?

    init(from course: Course) {
        self.id = course.id
        self.title = course.title
        self.durationDays = course.durationDays
        self.estimatedMinutes = course.estimatedMinutes
        self.savedAt = Date()
        self.placesData = (try? JSONEncoder().encode(course.places)) ?? Data()
        self.sourceCourseId = course.sourceCourseId.isEmpty ? nil : course.sourceCourseId
        self.journalText = nil
        self.journalImageData = nil
        self.journalImageUrl = nil
        self.visitedPlaceNamesData = nil
        self.exploredAt = nil
    }

    init(
        id: String,
        title: String,
        durationDays: Int,
        estimatedMinutes: Int,
        savedAt: Date = Date(),
        placesData: Data = Data(),
        journalText: String? = nil,
        journalImageData: Data? = nil,
        journalImageUrl: String? = nil,
        visitedPlaceNamesData: Data? = nil,
        exploredAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.durationDays = durationDays
        self.estimatedMinutes = estimatedMinutes
        self.savedAt = savedAt
        self.placesData = placesData
        self.journalText = journalText
        self.journalImageData = journalImageData
        self.journalImageUrl = journalImageUrl
        self.visitedPlaceNamesData = visitedPlaceNamesData
        self.exploredAt = exploredAt
    }

    var places: [CoursePlace] {
        (try? JSONDecoder().decode([CoursePlace].self, from: placesData)) ?? []
    }

    /// 탐험 결과 디코딩 — 저장된 방문 장소 이름 리스트
    var visitedPlaceNames: [String]? {
        guard let data = visitedPlaceNamesData else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }



}
