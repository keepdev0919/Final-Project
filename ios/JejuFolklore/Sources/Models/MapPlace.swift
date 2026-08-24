import Foundation
import CoreLocation

/// 지도 핀 하나. `GET /home/places`가 내려준다.
///
/// 지도 탭의 목적은 **「이 앱에 제주 콘텐츠가 몇 개 있지?」를 한눈에 보여주는 것**이다.
/// 그래서 이 모델은 카드처럼 풍부할 필요가 없다 — 핀을 찍고, 눌렀을 때 미니 카드에
/// 사진과 이름을 보여주고, 상세로 넘길 수 있으면 끝이다.
struct MapPlace: Codable, Identifiable, Equatable, Hashable {
    let name: String
    let lat: Double
    let lng: Double
    let stid: String
    let thumbnail: String?
    let storySeconds: Int

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

    /// 장소 상세 화면이 받는 형태로 바꾼다. **홈 카드가 가는 화면과 같은 화면이다.**
    var asCoursePlace: CoursePlace {
        CoursePlace(name: name, lat: lat, lng: lng, day: 0)
    }
}
