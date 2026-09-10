import Foundation
import CoreLocation
import Combine

/// 현재 위치를 **1회성으로만** 받아 오는 서비스.
///
/// 쓰이는 곳은 PLAY 진행 화면 하나다 — 다음 지점까지 남은 거리를 보여 주기 위해서다.
/// 진행 자체는 사용자가 「도착했어요」를 누르는 방식이라 연속 추적이 필요 없다.
///
/// 코스를 따라가며 도착을 자동 감지하던 기능은 2026-09-10에 걷어냈고,
/// 그에 딸렸던 연속 위치 갱신·체류 판정·도착 콜백도 함께 지웠다.
@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    /// 권한이 아직 안 나온 상태에서 1회성 위치를 요청받았는지.
    /// 권한 대화상자는 비동기라, 승인된 뒤에 다시 요청해야 한다.
    private var wantsOneShotLocation = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        authorizationStatus = manager.authorizationStatus
    }

    /// 다음 지점까지 남은 거리를 계산하기 위한 **1회성** 위치 요청.
    ///
    /// ⚠️ 받은 좌표는 **단말 안에서만** 쓴다. 서버로 보내지 않는다 (설계 §6).
    /// 이 불변식이 깨지면 위치기반서비스사업자 신고 대상이 된다.
    func requestCurrentLocationOnce() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            wantsOneShotLocation = false
            manager.requestLocation()
        case .notDetermined:
            wantsOneShotLocation = true
            manager.requestWhenInUseAuthorization()
        default:
            // 거부·제한 상태에서는 조용히 넘어간다. 거리가 안 보일 뿐 PLAY 는 끝까지 진행된다.
            wantsOneShotLocation = false
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
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

    /// `requestLocation()` 은 실패 콜백 구현을 요구한다.
    /// 위치를 못 받으면 거리 표시가 비는 것뿐이므로 조용히 넘어간다.
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.wantsOneShotLocation = false
        }
    }
}
