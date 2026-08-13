import Foundation
import CoreLocation

/// 여정 = 장소 1개 상품. v1은 성산 하나다.
/// 이야기 본문·오디오는 묶음 B에서 별도 모델로 붙는다.
struct Journey: Codable, Identifiable, Equatable {
    let journeyId: String
    let title: String
    let subtitle: String
    let theme: String
    let storyCount: Int
    let freeStoryCount: Int
    let totalMinutes: Int
    let priceKrw: Int
    let validDays: Int
    let coverImage: String?
    let ktoContentId: String
    let lat: Double
    let lng: Double

    var id: String { journeyId }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// "지금 여기예요" 배지를 띄울 거리. 성산 매표소~정상이 약 1km라 넉넉히 잡는다.
    static let hereThresholdMeters: CLLocationDistance = 800

    /// 사용자 위치와의 거리. **단말에서만 계산하고 서버로 보내지 않는다** (설계 §6).
    func isNearby(_ location: CLLocation?) -> Bool {
        guard let location else { return false }
        let target = CLLocation(latitude: lat, longitude: lng)
        return location.distance(from: target) <= Self.hereThresholdMeters
    }
}
