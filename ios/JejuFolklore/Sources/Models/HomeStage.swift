import Foundation
import CoreLocation

/// 홈 스테이지 카드 하나. `GET /home/stages`가 내려준다.
///
/// **홈은 장소 목록이 아니라 스테이지 선택 화면이다.** 그래서 카드가 장소를 설명하지 않고
/// **여기서 할 일**과 **내 상태**를 보여준다. 해설 길이·운영시간·방문 시간대 같은
/// 여행 정보는 전부 장소 상세 화면의 몫이다.
///
/// 어느 6곳을 띄우는지는 서버 `data/home_stage.json`이 정한다 — 라벨(종류)마다 1등 하나씩.
struct HomeStage: Codable, Identifiable, Equatable, Hashable {
    let name: String
    let lat: Double
    let lng: Double
    let stid: String
    /// KTO 실사 사진. 없을 수 있다.
    let thumbnail: String?
    /// 카드의 **유일한 문장**. 명령문이고, 눈앞에 실제로 있는 것을 가리킨다.
    let mission: String
    /// 세계관 라벨 — `화산` · `바다` · `물` · `숲` · `마을` · `옛터`
    let labelName: String
    /// 라벨 도트 아이콘 이름. `PixelIcon.Glyph`로 바꿔 쓴다.
    let labelIcon: String

    var id: String { stid }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// 장소 상세 화면이 받는 형태로 바꾼다.
    ///
    /// `PlaceDetailView`는 코스 안의 장소를 보여주려고 만든 화면이라 `CoursePlace`를 받는다.
    /// 홈에서 들어올 때는 코스가 없으므로 `day`는 의미 없는 0을 준다.
    var asCoursePlace: CoursePlace {
        CoursePlace(name: name, lat: lat, lng: lng, day: 0)
    }

    /// 라벨 이름을 도트 아이콘으로 옮긴다.
    ///
    /// ⚠️ 서버가 모르는 아이콘 이름을 보내면 `nil`이 되고 칩에 글자만 남는다.
    /// 카드가 깨지지는 않는다 — `data/home_stage.json`의 `icon` 값과 여기를 같이 고친다.
    var labelGlyph: PixelIcon.Glyph? {
        switch labelIcon {
        case "volcano": return .volcano
        case "wave":    return .wave
        case "drop":    return .drop
        case "tree":    return .tree
        case "house":   return .house
        case "gate":    return .gate
        default:        return nil
        }
    }
}
