import Foundation

enum PlaceAPI {
    static func detail(name: String, lat: Double, lng: Double) async throws -> PlaceDetail {
        try await APIClient.shared.get(
            "/place/detail",
            query: ["name": name, "lat": String(lat), "lng": String(lng)]
        )
    }

    /// 관광지 좌표 주변 화장실·정류장. ⚠️ 사용자 위치를 넘기지 말 것 — 관광지 좌표만.
    static func nearby(lat: Double, lng: Double) async throws -> PlaceNearby {
        try await APIClient.shared.get(
            "/place/nearby",
            query: ["lat": String(lat), "lng": String(lng)]
        )
    }
}
