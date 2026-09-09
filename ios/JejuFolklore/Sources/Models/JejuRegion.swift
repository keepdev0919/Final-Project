import SwiftUI
import UIKit
import CoreLocation

/// 제주 4개 권역. **백엔드와 같은 기준**이다
/// (`backend/scripts/build_curated_courses.py::_classify_place_region`).
///
/// 코스 탭의 지역 선택과 지도 탭의 지역 칩이 이걸 같이 쓴다. 두 화면이 다른 기준으로
/// 나누면 「동부에서 코스를 골랐는데 지도의 동부와 범위가 다른」 일이 생긴다.
///
/// ⚠️ 경계값을 바꾸면 백엔드도 같이 바꿔야 한다. 한쪽만 바꾸면 코스 목록과 지도가
/// 조용히 어긋난다 — 화면은 멀쩡하고 결과만 달라진다.
struct JejuRegionDef {
    let id: String
    let label: String
    let sublabel: String
    /// 권역색. **앱 전체에서 이 색 하나가 이 권역을 가리킨다** — 코스 카드 배지,
    /// 코스 탭 픽셀 제주 지도의 권역 버튼, 지도 탭 권역 칩이 같이 쓴다
    /// (2026-09-09 조익준님 결정). 색 값과 배정 이유는 `PixelColor` 에 있다.
    let color: Color
    /// 권역색 위에 올리는 글자색. 짝을 안 맞추면 배지에서 이름이 사라진다.
    let onColor: Color

    // 백엔드 GPS 필터와 동일한 기준으로 좌표가 어느 지역인지 판별
    func contains(_ coord: CLLocationCoordinate2D) -> Bool {
        switch id {
        case "서부": return coord.longitude < 126.40
        case "북부": return coord.latitude >= 33.45
        case "동부": return coord.longitude >= 126.70
        case "남부": return coord.latitude < 33.30
        default:     return false
        }
    }

    // 지역 폴리곤 좌표 (섬 전체 bounding box 내 직사각형 섹터)
    var polygonCoords: [CLLocationCoordinate2D] {
        switch id {
        case "서부":
            return [
                CLLocationCoordinate2D(latitude: 33.57, longitude: 126.10),
                CLLocationCoordinate2D(latitude: 33.57, longitude: 126.40),
                CLLocationCoordinate2D(latitude: 33.10, longitude: 126.40),
                CLLocationCoordinate2D(latitude: 33.10, longitude: 126.10),
            ]
        case "북부":
            return [
                CLLocationCoordinate2D(latitude: 33.57, longitude: 126.40),
                CLLocationCoordinate2D(latitude: 33.57, longitude: 126.70),
                CLLocationCoordinate2D(latitude: 33.45, longitude: 126.70),
                CLLocationCoordinate2D(latitude: 33.45, longitude: 126.40),
            ]
        case "동부":
            return [
                CLLocationCoordinate2D(latitude: 33.57, longitude: 126.70),
                CLLocationCoordinate2D(latitude: 33.57, longitude: 126.97),
                CLLocationCoordinate2D(latitude: 33.10, longitude: 126.97),
                CLLocationCoordinate2D(latitude: 33.10, longitude: 126.70),
            ]
        case "남부":
            return [
                CLLocationCoordinate2D(latitude: 33.30, longitude: 126.40),
                CLLocationCoordinate2D(latitude: 33.30, longitude: 126.70),
                CLLocationCoordinate2D(latitude: 33.10, longitude: 126.70),
                CLLocationCoordinate2D(latitude: 33.10, longitude: 126.40),
            ]
        default:
            return []
        }
    }

    // 레이블 표시 위치
    var labelCoord: CLLocationCoordinate2D {
        switch id {
        case "서부": return CLLocationCoordinate2D(latitude: 33.38, longitude: 126.24)
        case "북부": return CLLocationCoordinate2D(latitude: 33.51, longitude: 126.52)
        case "동부": return CLLocationCoordinate2D(latitude: 33.38, longitude: 126.83)
        case "남부": return CLLocationCoordinate2D(latitude: 33.22, longitude: 126.55)
        default:     return CLLocationCoordinate2D(latitude: 33.36, longitude: 126.53)
        }
    }

    /// 「전체」의 id. 백엔드가 쓰는 값 그대로다 — 코스의 장소가 한 권역에
    /// 과반으로 몰리지 않으면 백엔드가 이 값을 준다 (`build_curated_courses.py`).
    static let wholeIslandID = "전체"

    /// ⚠️ 전에는 권역색이 `primary`(초록)·`locked`(빨강)까지 끌어다 썼다. 초록은
    /// 「플레이 시작」이고 빨강은 「잠김·오류」라, 남부가 빨강이면 코스 카드가
    /// 경고처럼 읽힌다. 게다가 이 필드는 정의만 되어 있고 화면 어디서도 쓰지
    /// 않고 있었다 — 지금 세 화면이 실제로 쓰기 시작한다 (2026-09-09).
    static let all: [JejuRegionDef] = [
        JejuRegionDef(id: "서부", label: "서부", sublabel: "한림·애월",
                      color: PixelColor.regionWest,  onColor: PixelColor.onRegionWest),
        JejuRegionDef(id: "북부", label: "북부", sublabel: "제주시",
                      color: PixelColor.regionNorth, onColor: PixelColor.onRegionNorth),
        JejuRegionDef(id: "동부", label: "동부", sublabel: "성산·구좌",
                      color: PixelColor.regionEast,  onColor: PixelColor.onRegionEast),
        JejuRegionDef(id: "남부", label: "남부", sublabel: "서귀포",
                      color: PixelColor.regionSouth, onColor: PixelColor.onRegionSouth),
    ]

    static func find(_ id: String) -> JejuRegionDef? {
        all.first { $0.id == id }
    }

    /// 권역 id 로 색을 찾는다. **모르는 id 와 「전체」는 잉크**다 — 색조를 주면
    /// 「전체」가 다섯 번째 권역처럼 보인다. 실제로는 권역을 안 가린다는 뜻이다.
    static func colors(for id: String) -> (fill: Color, on: Color) {
        guard let region = find(id) else {
            return (PixelColor.regionAll, PixelColor.onRegionAll)
        }
        return (region.color, region.onColor)
    }
}
