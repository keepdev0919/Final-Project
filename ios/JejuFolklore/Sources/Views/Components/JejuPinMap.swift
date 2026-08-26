import SwiftUI
import GoogleMaps

/// 제주 지도에 핀을 찍는 뷰. 지도 탭이 쓴다.
///
/// `GoogleMapPreview`와 다른 물건이다 — 그쪽은 마커 하나에 조작이 막힌 미리보기고,
/// 이쪽은 핀 수십~수백 개에 손으로 움직이는 지도다. 같은 파일에 두면 둘 다 복잡해진다.
///
/// ## 핀을 매번 다시 그리지 않는다
///
/// `updateUIView`는 SwiftUI가 아무 상태를 바꿔도 불린다. 여기서 마커를 전부 지우고
/// 다시 만들면 **핀 103개를 만드는 일이 화면을 만질 때마다 반복**되고, 눌린 핀의
/// 선택 상태도 매번 날아간다. 그래서 이미 그린 장소를 `Coordinator`가 기억한다.
struct JejuPinMap: UIViewRepresentable {
    let places: [MapPlace]
    let focus: JejuMapFocus
    @Binding var selected: MapPlace?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.frame = .zero
        options.camera = GMSCameraPosition.camera(withLatitude: 33.36, longitude: 126.53, zoom: 8.6)
        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator
        mapView.settings.compassButton = false
        mapView.settings.myLocationButton = false
        // 지도 자체는 픽셀아트가 아니다. 핀이 읽히도록 바탕을 조용하게 둔다
        // (`docs/공유/Stitch-프롬프트_지도.md` 화면 1).
        mapView.settings.tiltGestures = false
        mapView.settings.rotateGestures = false
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncMarkers(on: mapView, places: places)
        context.coordinator.applyFocus(focus, on: mapView)
        context.coordinator.highlight(selected, on: mapView)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: JejuPinMap
        /// 이미 그린 핀. 키는 `MapPlace.id`(stid)다.
        private var markers: [String: GMSMarker] = [:]
        private var appliedFocus: JejuMapFocus?
        private var highlightedId: String?

        init(_ parent: JejuPinMap) {
            self.parent = parent
        }

        /// 없는 핀만 만들고, 사라진 핀만 지운다.
        func syncMarkers(on mapView: GMSMapView, places: [MapPlace]) {
            let wanted = Set(places.map(\.id))
            for (id, marker) in markers where !wanted.contains(id) {
                marker.map = nil
                markers.removeValue(forKey: id)
            }
            for place in places where markers[place.id] == nil {
                let marker = GMSMarker(position: place.coordinate)
                marker.userData = place
                marker.icon = Self.pinImage(selected: false)
                marker.groundAnchor = Self.pinAnchor
                // 기본 정보창을 쓰지 않는다. 우리 미니 카드가 그 일을 한다.
                marker.tracksInfoWindowChanges = false
                marker.map = mapView
                markers[place.id] = marker
            }
        }

        /// 지역 칩이 바뀌었을 때만 카메라를 옮긴다. 매번 옮기면 사용자가 지도를
        /// 손으로 끌어놓은 위치가 계속 되돌아간다.
        func applyFocus(_ focus: JejuMapFocus, on mapView: GMSMapView) {
            guard appliedFocus != focus else { return }
            appliedFocus = focus
            let update = GMSCameraUpdate.fit(focus.bounds, withPadding: 24)
            mapView.animate(with: update)
        }

        /// 눌린 핀만 크고 진하게. 색만으로 구분하지 않으려고 크기도 같이 키운다.
        func highlight(_ place: MapPlace?, on mapView: GMSMapView) {
            guard highlightedId != place?.id else { return }
            if let previous = highlightedId, let marker = markers[previous] {
                marker.icon = Self.pinImage(selected: false)
                marker.zIndex = 0
            }
            highlightedId = place?.id
            if let id = place?.id, let marker = markers[id] {
                marker.icon = Self.pinImage(selected: true)
                marker.zIndex = 1
            }
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let place = marker.userData as? MapPlace else { return false }
            parent.selected = place
            // true를 돌려주면 구글의 기본 동작(정보창 열기 + 카메라 중앙 이동)을 막는다.
            // 카메라가 움직이면 사용자가 보고 있던 주변 핀들이 흐트러진다.
            return true
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            parent.selected = nil
        }

        // MARK: - 핀 그림

        /// 도트 핀. **아래로 뾰족해서 「그 지점」을 가리키는 것으로 읽힌다** —
        /// 사각형만 그렸을 때는 지도 위에 놓인 타일처럼 보였다(2026-08-26 조익준님 지적).
        ///
        /// 격자로 적는 이유는 `PixelIcon`과 같다 — 모양을 데이터로 두면 눈으로 고칠 수 있다.
        /// `X`가 잉크 테두리, `o`가 채움, `.`이 투명이다.
        ///
        /// ⚠️ 구글 기본 물방울 마커(`GMSMarker.markerImage`)를 쓰지 않는다.
        /// 둥글고 그라디언트가 들어가서 우리 화면에서 혼자 이질적으로 보인다
        /// (`DESIGN.md` §5 — 반경 0, 잉크 테두리).
        private static let pinGrid = [
            ".XXXXXX.",
            "XooooooX",
            "XooooooX",
            "XooooooX",
            "XooooooX",
            ".XooooX.",
            "..XooX..",
            "...XX...",
        ]

        /// 핀 꼭짓점이 좌표에 닿게 하는 기준점. 격자 맨 아래 가운데다.
        /// 이걸 안 주면 핀의 **중심**이 좌표에 놓여서 실제 지점보다 아래를 가리킨다.
        private static let pinAnchor = CGPoint(x: 0.5, y: 1.0)

        private static func pinImage(selected: Bool) -> UIImage {
            let unit: CGFloat = selected ? 3 : 2
            let cols = CGFloat(pinGrid[0].count)
            let rows = CGFloat(pinGrid.count)
            let size = CGSize(width: cols * unit, height: rows * unit)

            return UIGraphicsImageRenderer(size: size).image { ctx in
                let cg = ctx.cgContext
                // 선택된 핀은 채움을 강조색으로 바꾼다. 크기도 같이 키워서
                // **색만으로 구분하지 않는다**(DESIGN.md §7 접근성).
                let fill = selected ? PixelUIColor.accent : PixelUIColor.primary
                for (y, row) in pinGrid.enumerated() {
                    for (x, char) in row.enumerated() where char != "." {
                        cg.setFillColor(char == "X" ? PixelUIColor.ink.cgColor : fill.cgColor)
                        cg.fill(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit,
                                       width: unit, height: unit))
                    }
                }
            }
        }
    }
}
