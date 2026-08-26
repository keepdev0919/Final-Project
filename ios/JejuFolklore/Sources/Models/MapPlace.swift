import Foundation
import CoreLocation

/// 한 장소에 딸린 해설 하나.
///
/// 오디는 **장소가 아니라 해설 단위**로 데이터를 준다. 관음사는 일주문·사천왕문·대웅전…
/// 10개의 해설이 각각 좌표를 갖고 따로 온다. 서버가 300m로 묶어 한 장소로 만들되
/// **해설은 하나도 버리지 않는다** — 나중에 지점·미션을 만들 재료가 이것이다.
struct PlaceStory: Codable, Identifiable, Equatable, Hashable {
    let stid: String
    let title: String
    let seconds: Int
    let lat: Double
    let lng: Double

    var id: String { stid }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

/// 지도 핀 하나. `GET /home/places`가 내려준다.
///
/// 지도 탭의 목적은 **「이 앱에 제주 콘텐츠가 몇 개 있지?」를 한눈에 보여주는 것**이다.
/// 그래서 이 모델은 카드처럼 풍부할 필요가 없다 — 핀을 찍고, 눌렀을 때 미니 카드에
/// 사진·이름·해설 분량을 보여주고, 상세로 넘길 수 있으면 끝이다.
struct MapPlace: Codable, Identifiable, Equatable, Hashable {
    let name: String
    let lat: Double
    let lng: Double
    /// 대표 해설(가장 가까운 것)의 식별자. 목록의 키로도 쓴다.
    let stid: String
    let thumbnail: String?
    /// ⚠️ **이 장소 해설 전부의 합계 시간**이다. 대표 하나의 길이가 아니다.
    let storySeconds: Int
    let storyCount: Int
    let stories: [PlaceStory]

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

    /// 해설이 여럿인 곳은 개수를 같이 보여준다 — 관음사는 「해설 10개 · 6분 53초」다.
    /// 개수를 숨기면 절 하나에 3분짜리 하나만 있는 것처럼 읽힌다.
    var storySummary: String {
        storyCount > 1
            ? "해설 \(storyCount)개 · \(storyDurationText)"
            : "해설 \(storyDurationText)"
    }

    /// 장소 상세 화면이 받는 형태로 바꾼다. **홈 카드가 가는 화면과 같은 화면이다.**
    var asCoursePlace: CoursePlace {
        CoursePlace(name: name, lat: lat, lng: lng, day: 0)
    }
}
