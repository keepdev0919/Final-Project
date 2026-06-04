import Foundation
import SwiftData
import FirebaseFirestore

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
    var journalImageUrl: String?
    var visitedPlaceNamesData: Data?   // JSON-encoded [String]
    var exploredAt: Date?

    // MARK: - Firestore sync fields (Optional for auto-migration)
    /// 소유 사용자 UID. nil이면 익명(로컬 전용) 코스.
    var userId: String?
    /// Firestore 서버 기준 마지막 업데이트 시각 (LWW 비교용).
    var serverUpdatedAt: Date?

    init(from course: Course) {
        self.id = course.id
        self.title = course.title
        self.durationDays = course.durationDays
        self.estimatedMinutes = course.estimatedMinutes
        self.savedAt = Date()
        self.placesData = (try? JSONEncoder().encode(course.places)) ?? Data()
        self.journalText = nil
        self.journalImageData = nil
        self.journalImageUrl = nil
        self.visitedPlaceNamesData = nil
        self.exploredAt = nil
        self.userId = nil
        self.serverUpdatedAt = nil
    }

    /// Firestore 동기화/마이그레이션에서 사용하는 빈 초기화.
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
        exploredAt: Date? = nil,
        userId: String? = nil,
        serverUpdatedAt: Date? = nil
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
        self.userId = userId
        self.serverUpdatedAt = serverUpdatedAt
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

// MARK: - Firestore DTO

extension SavedCourse {
    /// Firestore 문서로 직렬화. `updatedAt`은 서버 타임스탬프를 사용한다.
    func toFirestoreData() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "durationDays": durationDays,
            "estimatedMinutes": estimatedMinutes,
            "savedAt": Timestamp(date: savedAt),
            "updatedAt": FieldValue.serverTimestamp(),
        ]

        // places: JSON 데이터를 디코드해서 [[String: Any]] 형태로 직렬화
        let decodedPlaces = places
        if let placesJSON = try? JSONEncoder().encode(decodedPlaces),
           let placesArray = try? JSONSerialization.jsonObject(with: placesJSON) as? [[String: Any]] {
            dict["places"] = placesArray
        }

        if let journalText {
            dict["journalText"] = journalText
        }
        if let journalImageUrl {
            dict["journalImageUrl"] = journalImageUrl
        }
        if let names = visitedPlaceNames {
            dict["visitedPlaceNames"] = names
        }
        if let exploredAt {
            dict["exploredAt"] = Timestamp(date: exploredAt)
        }
        if let userId {
            dict["userId"] = userId
        }
        return dict
    }

    /// Firestore에서 받은 dict로 기존 SavedCourse를 upsert.
    /// 기존 모델이 있으면 필드 업데이트, 없으면 신규 insert.
    @MainActor
    static func upsert(from dict: [String: Any], id: String, into context: ModelContext) {
        // 기존 모델 조회
        let descriptor = FetchDescriptor<SavedCourse>(
            predicate: #Predicate<SavedCourse> { $0.id == id }
        )
        let existing = (try? context.fetch(descriptor))?.first

        let title = dict["title"] as? String ?? "(제목 없음)"
        let durationDays = dict["durationDays"] as? Int ?? 1
        let estimatedMinutes = dict["estimatedMinutes"] as? Int ?? 0

        let savedAt: Date = {
            if let ts = dict["savedAt"] as? Timestamp { return ts.dateValue() }
            if let d = dict["savedAt"] as? Date { return d }
            return Date()
        }()

        let serverUpdatedAt: Date? = {
            if let ts = dict["updatedAt"] as? Timestamp { return ts.dateValue() }
            if let d = dict["updatedAt"] as? Date { return d }
            return nil
        }()

        let placesData: Data = {
            if let arr = dict["places"] as? [[String: Any]],
               let data = try? JSONSerialization.data(withJSONObject: arr) {
                return data
            }
            return Data()
        }()

        let journalText = dict["journalText"] as? String
        let journalImageUrl = dict["journalImageUrl"] as? String
        let visitedNames = dict["visitedPlaceNames"] as? [String]
        let visitedData = visitedNames.flatMap { try? JSONEncoder().encode($0) }
        let exploredAt: Date? = {
            if let ts = dict["exploredAt"] as? Timestamp { return ts.dateValue() }
            if let d = dict["exploredAt"] as? Date { return d }
            return nil
        }()
        let userId = dict["userId"] as? String

        if let existing {
            // LWW: 서버 timestamp가 더 최신일 때만 덮어쓴다
            if let incoming = serverUpdatedAt,
               let local = existing.serverUpdatedAt,
               incoming <= local {
                return
            }
            existing.title = title
            existing.durationDays = durationDays
            existing.estimatedMinutes = estimatedMinutes
            existing.savedAt = savedAt
            existing.placesData = placesData
            existing.journalText = journalText
            existing.journalImageUrl = journalImageUrl
            existing.visitedPlaceNamesData = visitedData
            existing.exploredAt = exploredAt
            existing.userId = userId
            existing.serverUpdatedAt = serverUpdatedAt
        } else {
            let new = SavedCourse(
                id: id,
                title: title,
                durationDays: durationDays,
                estimatedMinutes: estimatedMinutes,
                savedAt: savedAt,
                placesData: placesData,
                journalText: journalText,
                journalImageData: nil,
                journalImageUrl: journalImageUrl,
                visitedPlaceNamesData: visitedData,
                exploredAt: exploredAt,
                userId: userId,
                serverUpdatedAt: serverUpdatedAt
            )
            context.insert(new)
        }
    }
}
