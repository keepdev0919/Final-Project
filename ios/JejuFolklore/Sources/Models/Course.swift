import Foundation

struct Course: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let durationDays: Int
    let places: [CoursePlace]
    let estimatedMinutes: Int
    let sourceCourseId: String

    init(id: String, title: String, durationDays: Int, places: [CoursePlace],
         estimatedMinutes: Int, sourceCourseId: String = "") {
        self.id = id
        self.title = title
        self.durationDays = durationDays
        self.places = places
        self.estimatedMinutes = estimatedMinutes
        self.sourceCourseId = sourceCourseId
    }
}

// 코스 리스트 화면용 경량 모델
struct CourseListItem: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let durationDays: Int
    /// 동부 | 서부 | 남부 | 북부 | 전체. 코스 카드의 권역색 배지가 쓴다.
    ///
    /// **옵셔널이다.** 서버가 이 값을 내려주기 시작한 게 나중이라(2026-09-09),
    /// 값이 없는 응답이 오면 `nil` 로 두고 「전체」처럼 다룬다. 필수로 두면
    /// 예전 응답 하나에 목록 전체가 디코딩 실패로 사라진다.
    let region: String?
    /// 대표 장소(제목에 뜨는 그 장소)의 KTO 대표사진. 서버 캐시에 없으면 nil —
    /// 그때는 카드가 권역색 픽셀 블록을 깐다.
    let thumbnail: String?
    let places: [CoursePlace]

    /// 화면이 쓰는 권역. 서버가 안 주면 「전체」다.
    var regionOrAll: String { region ?? JejuRegionDef.wholeIslandID }

    /// 제목 앞의 「서부 3일 · 」 같은 접두사를 뗀 나머지.
    ///
    /// 백엔드가 제목을 `{권역} {일수}일 · {대표장소} 외 N곳` 으로 만든다
    /// (`build_curated_courses.py::_make_title`). 카드가 권역을 배지로, 일수를
    /// 아래 줄로 따로 보여주게 되면서 제목에 같은 사실이 두 번 나오게 됐다.
    /// 그래서 **화면에서만** 접두사를 뗀다 — 원본 제목은 그대로 둔다.
    var placeHeadline: String {
        let region = regionOrAll
        var t = title
        if t.hasPrefix(region + " ") { t.removeFirst(region.count + 1) }
        // 「3일 · 」 / 「3일 코스」 두 형태를 모두 뗀다.
        if let dot = t.range(of: "일 · "), t[t.startIndex..<dot.lowerBound].allSatisfy(\.isNumber) {
            t = String(t[dot.upperBound...])
        }
        return t.isEmpty ? title : t
    }
}
