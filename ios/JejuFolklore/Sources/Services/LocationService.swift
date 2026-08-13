import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var visitedPlaceIDs: Set<String> = []
    /// 권한이 아직 안 나온 상태에서 1회성 위치를 요청받았는지.
    /// 권한 대화상자는 비동기라, 승인된 뒤에 다시 요청해야 한다.
    private var wantsOneShotLocation = false

    var onArrival: ((String) -> Void)?  // (placeName)

    // 탐험 중인 코스 장소 목록
    private var activePlaces: [CoursePlace] = []
    private var transportMode: String = "car"  // "car" | "walk"
    private var pendingArrivals: [String: Date] = [:]
    #if DEBUG
    private let dwellRequired: TimeInterval = 3
    #else
    private let dwellRequired: TimeInterval = 30
    #endif

    private var arrivalRadius: Double {
        #if DEBUG
        return 99999.0
        #else
        return transportMode == "walk" ? 100.0 : 300.0
        #endif
    }

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// 홈·스토리 탭의 "지금 여기예요" 판정을 위한 **1회성** 위치 요청.
    ///
    /// 탐험 중이 아닐 때도 현재 위치가 필요하지만, 배터리를 위해 지속 추적은 하지 않는다.
    /// 권한 대화상자가 비동기라 아직 미결정이면 승인 시점에 자동으로 다시 요청한다.
    ///
    /// ⚠️ 받은 좌표는 **단말 안에서만** 쓴다. 서버로 보내지 않는다 (설계 §6).
    func requestCurrentLocationOnce() {
        // 탐험 중이면 이미 연속 갱신되고 있다.
        guard activePlaces.isEmpty else { return }

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            wantsOneShotLocation = false
            manager.requestLocation()
        case .notDetermined:
            wantsOneShotLocation = true
            manager.requestWhenInUseAuthorization()
        default:
            // 거부·제한 상태에서는 조용히 넘어간다. 배지가 안 뜰 뿐 앱은 정상 동작한다.
            wantsOneShotLocation = false
        }
    }

    func startExploring(places: [CoursePlace], transport: String, alreadyVisited: Set<String> = []) {
        activePlaces = places
        transportMode = transport
        // 세션 복원 시 이미 방문한 장소의 placeID를 미리 등록해 재감지를 방지한다
        visitedPlaceIDs = Set(
            places
                .filter { alreadyVisited.contains($0.name) }
                .map { "\($0.name)-\($0.day)" }
        )
        pendingArrivals.removeAll()
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
    }

    func stopExploring() {
        activePlaces = []
        pendingArrivals.removeAll()
        manager.allowsBackgroundLocationUpdates = false
        manager.stopUpdatingLocation()
    }

    private func checkArrival(for location: CLLocation) {
        for place in activePlaces {
            let placeID = "\(place.name)-\(place.day)"
            guard !visitedPlaceIDs.contains(placeID) else { continue }

            let target = CLLocation(latitude: place.lat, longitude: place.lng)
            let distance = location.distance(from: target)

            if distance <= arrivalRadius {
                if let enteredAt = pendingArrivals[placeID] {
                    if Date().timeIntervalSince(enteredAt) >= dwellRequired {
                        visitedPlaceIDs.insert(placeID)
                        pendingArrivals.removeValue(forKey: placeID)
                        onArrival?(place.name)
                    }
                } else {
                    pendingArrivals[placeID] = Date()
                }
            } else {
                pendingArrivals.removeValue(forKey: placeID)
            }
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            self.checkArrival(for: location)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            // 권한 대화상자를 방금 승인했다면, 보류해 둔 1회성 요청을 이어서 보낸다.
            if self.wantsOneShotLocation {
                self.requestCurrentLocationOnce()
            }
        }
    }

    /// `requestLocation()`은 실패 콜백 구현을 요구한다.
    /// 위치를 못 받으면 "지금 여기예요" 배지가 안 뜰 뿐이므로 조용히 넘어간다.
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.wantsOneShotLocation = false
        }
    }
}
