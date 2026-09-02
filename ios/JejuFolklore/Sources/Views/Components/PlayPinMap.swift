import SwiftUI
import GoogleMaps

/// PLAY 지도의 핀.
///
/// 두 가지 상태를 **색과 모양 둘 다로** 구분한다 (접근성).
///
///     플레이 가능  속이 찬 초록 핀 + 가운데 점
///     준비 중      속이 빈 회색 핀
///
/// 색만 다르게 하면 색각 이상이 있는 사용자에게 두 상태가 같아 보인다.
///
/// ## 핀을 매번 다시 그리지 않는다
///
/// `updateUIView` 는 SwiftUI 가 아무 상태를 바꿔도 불린다. 여기서 마커를 전부
/// 지우고 다시 만들면 선택 상태가 매번 날아간다. 그래서 이미 그린 핀을
/// `Coordinator` 가 기억한다.
struct PlayPinMap: UIViewRepresentable {
    let pins: [PlayMapPin]
    let focus: JejuMapFocus
    @Binding var selected: PlayMapPin?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.frame = .zero
        options.camera = GMSCameraPosition.camera(withLatitude: 33.36,
                                                  longitude: 126.53, zoom: 8.6)
        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator
        mapView.settings.compassButton = false
        mapView.settings.myLocationButton = false
        // 지도 바탕은 픽셀아트가 아니다. 핀이 읽히도록 조용하게 둔다.
        mapView.settings.tiltGestures = false
        mapView.settings.rotateGestures = false
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(pins, on: mapView)
        context.coordinator.applyFocus(focus, on: mapView)
        context.coordinator.highlight(selected, on: mapView)
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: PlayPinMap
        private var markers: [String: GMSMarker] = [:]
        private var appliedFocus: JejuMapFocus?
        private var highlightedId: String?

        init(_ parent: PlayPinMap) { self.parent = parent }

        func sync(_ pins: [PlayMapPin], on mapView: GMSMapView) {
            let wanted = Set(pins.map(\.id))
            for (id, marker) in markers where !wanted.contains(id) {
                marker.map = nil
                markers.removeValue(forKey: id)
            }
            for pin in pins where markers[pin.id] == nil {
                let marker = GMSMarker(position: pin.coordinate)
                marker.userData = pin
                marker.icon = Self.pinImage(status: pin.status, selected: false)
                marker.groundAnchor = Self.pinAnchor
                marker.tracksInfoWindowChanges = false
                marker.map = mapView
                markers[pin.id] = marker
            }
        }

        /// 지역 칩이 바뀌었을 때만 카메라를 옮긴다. 매번 옮기면 사용자가 손으로
        /// 끌어놓은 위치가 계속 되돌아간다.
        func applyFocus(_ focus: JejuMapFocus, on mapView: GMSMapView) {
            guard appliedFocus != focus else { return }
            appliedFocus = focus
            mapView.animate(with: GMSCameraUpdate.fit(focus.bounds, withPadding: 40))
        }

        func highlight(_ pin: PlayMapPin?, on mapView: GMSMapView) {
            guard highlightedId != pin?.id else { return }
            if let prev = highlightedId, let m = markers[prev],
               let p = m.userData as? PlayMapPin {
                m.icon = Self.pinImage(status: p.status, selected: false)
                m.zIndex = 0
            }
            highlightedId = pin?.id
            if let id = pin?.id, let m = markers[id], let p = pin {
                m.icon = Self.pinImage(status: p.status, selected: true)
                m.zIndex = 1
            }
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let pin = marker.userData as? PlayMapPin else { return false }
            parent.selected = pin
            // true 를 돌려주면 구글의 기본 동작(정보창 + 카메라 이동)을 막는다.
            // 카메라가 움직이면 보고 있던 주변 핀들이 흐트러진다.
            return true
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            parent.selected = nil
        }

        // MARK: - 핀 그림

        /// 아래로 뾰족한 도트 핀. 구글 기본 물방울 마커는 둥글고 그라디언트가 있어
        /// 우리 화면에서 혼자 이질적으로 보인다 (반경 0, 잉크 테두리).
        ///
        /// `X` 잉크 테두리 · `o` 채움 · `+` 가운데 점(플레이 가능 표시) · `.` 투명
        private static let activeGrid = [
            ".XXXXXX.",
            "XooooooX",
            "Xo+  +oX",
            "Xo+++ oX",
            "Xoo++ oX",
            ".XooooX.",
            "..XooX..",
            "...XX...",
        ]

        /// 준비 중은 **속이 비어 있다.** 색을 못 봐도 구분된다.
        private static let preparingGrid = [
            ".XXXXXX.",
            "X......X",
            "X......X",
            "X......X",
            "X......X",
            ".X....X.",
            "..X..X..",
            "...XX...",
        ]

        /// 핀 꼭짓점이 좌표에 닿게 하는 기준점. 격자 맨 아래 가운데다.
        private static let pinAnchor = CGPoint(x: 0.5, y: 1.0)

        private static func pinImage(status: PlayMapPin.Status,
                                     selected: Bool) -> UIImage {
            let grid = status == .active ? activeGrid : preparingGrid
            // 플레이 가능한 곳을 더 크게. 크기로도 중요도가 읽힌다.
            let base: CGFloat = status == .active ? 3 : 2
            let unit = selected ? base + 1 : base
            let cols = CGFloat(grid[0].count), rows = CGFloat(grid.count)
            let size = CGSize(width: cols * unit, height: rows * unit)

            return UIGraphicsImageRenderer(size: size).image { ctx in
                let cg = ctx.cgContext
                let fill = selected ? PixelUIColor.accent
                                    : (status == .active ? PixelUIColor.primary
                                                         : PixelUIColor.surface)
                let ink = status == .active ? PixelUIColor.ink : PixelUIColor.locked
                for (y, row) in grid.enumerated() {
                    for (x, ch) in row.enumerated() where ch != "." {
                        let color: UIColor
                        switch ch {
                        case "X": color = ink
                        case "+": color = PixelUIColor.surface   // 가운데 점
                        default:  color = fill
                        }
                        cg.setFillColor(color.cgColor)
                        cg.fill(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit,
                                       width: unit, height: unit))
                    }
                }
            }
        }
    }
}
