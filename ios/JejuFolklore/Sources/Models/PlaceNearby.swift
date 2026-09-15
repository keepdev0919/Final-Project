import Foundation

/// 관광지 좌표 주변 1km 의 공중화장실과 버스정류장 (`/place/nearby`).
///
/// 화장실은 제주시 데이터, 정류장은 국토교통부 TAGO 데이터다. 둘 다 **관광지 좌표**로
/// 물어본 결과라 사용자 위치는 서버로 가지 않는다.
struct PlaceNearby: Decodable {
    let toilets: [NearbyFacility]
    let busStops: [NearbyFacility]

    var isEmpty: Bool { toilets.isEmpty && busStops.isEmpty }
}

struct NearbyFacility: Decodable, Hashable {
    let name: String
    let distanceM: Int
    let lat: Double
    let lng: Double
    /// 화장실만. 정류장은 nil.
    let openTime: String?
    /// 화장실만 — 장애인용 변기가 하나라도 있는가.
    let accessible: Bool?

    /// 「95m」 / 「1.2km」
    var distanceText: String {
        distanceM < 1000 ? "\(distanceM)m" : String(format: "%.1fkm", Double(distanceM) / 1000)
    }
}
