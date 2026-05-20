import SwiftUI
import GoogleMaps

/// SwiftUI 에서 Google Maps 를 미리보기로 임베드하기 위한 UIViewRepresentable 래퍼.
/// 단일 마커 + 카메라 줌만 지원하는 가벼운 프리뷰용.
struct GoogleMapPreview: UIViewRepresentable {
    let lat: Double
    let lng: Double
    var zoom: Float = 15.0
    var markerTitle: String? = nil

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(withLatitude: lat, longitude: lng, zoom: zoom)
        let options = GMSMapViewOptions()
        options.camera = camera
        options.frame = .zero
        let mapView = GMSMapView(options: options)
        mapView.isUserInteractionEnabled = false
        mapView.settings.setAllGesturesEnabled(false)
        mapView.settings.compassButton = false
        mapView.settings.myLocationButton = false

        let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: lat, longitude: lng))
        marker.title = markerTitle
        marker.icon = GMSMarker.markerImage(with: .orange)
        marker.map = mapView
        return mapView
    }

    func updateUIView(_ uiView: GMSMapView, context: Context) {
        let camera = GMSCameraPosition.camera(withLatitude: lat, longitude: lng, zoom: zoom)
        uiView.animate(to: camera)
    }
}
