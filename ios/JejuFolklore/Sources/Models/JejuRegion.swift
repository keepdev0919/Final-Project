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
    let uiColor: UIColor

    var swiftUIColor: Color { Color(uiColor: uiColor) }

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

    static let all: [JejuRegionDef] = [
        JejuRegionDef(id: "서부", label: "서부", sublabel: "한림·애월",  uiColor: PixelUIColor.primary),
        JejuRegionDef(id: "북부", label: "북부", sublabel: "제주시",     uiColor: PixelUIColor.secondary),
        JejuRegionDef(id: "동부", label: "동부", sublabel: "성산·구좌",  uiColor: PixelUIColor.tertiary),
        JejuRegionDef(id: "남부", label: "남부", sublabel: "서귀포",     uiColor: PixelUIColor.locked),
    ]

    static func find(_ id: String) -> JejuRegionDef? {
        all.first { $0.id == id }
    }
}
