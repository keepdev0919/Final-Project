import Foundation
import CoreLocation

/// 홈 장소 카드 하나. `GET /home/places`가 내려준다.
///
/// 실제 여행자 일정에 많이 담긴 순서로 뽑되, 오디 해설이 있는 곳만 온다.
/// 계산 규칙은 서버 `services/home_places.py`에 있다.
struct HomePlace: Codable, Identifiable, Equatable, Hashable {
    /// 여행자가 부르는 이름 (비짓제주). 괄호 부가설명은 서버가 뗀 상태로 온다.
    let name: String
    let lat: Double
    let lng: Double
    /// 이 장소가 등장한 실제 여행 일정 수.
    let courseCount: Int
    /// 오디 해설 식별자. 재생할 때 쓴다.
    let stid: String
    let storyTitle: String?
    let storySeconds: Int
    /// KTO 실사 사진 주소. 서버가 미리 받아 저장한 것으로, 없을 수 있다
    /// (`scripts/warm_home_thumbnails.py`를 안 돌렸거나 KTO에 사진이 없는 곳).
    let thumbnail: String?

    var id: String { stid }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// "3분 7초" — 1분 미만이면 초만 쓴다.
    var storyDurationText: String {
        let m = storySeconds / 60, s = storySeconds % 60
        if m == 0 { return "\(s)초" }
        return s == 0 ? "\(m)분" : "\(m)분 \(s)초"
    }

    /// 장소 상세 화면이 받는 형태로 바꾼다.
    ///
    /// `PlaceDetailView`는 코스 안의 장소를 보여주려고 만든 화면이라 `CoursePlace`를 받는다.
    /// 홈에서 들어올 때는 코스가 없으므로 `day`는 의미 없는 0을 준다.
    var asCoursePlace: CoursePlace {
        CoursePlace(name: name, lat: lat, lng: lng, day: 0)
    }
}
