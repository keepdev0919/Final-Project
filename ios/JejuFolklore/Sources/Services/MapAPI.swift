import Foundation

/// 지도 탭용 API.
///
/// `/home/places`를 **전부** 받는다. 「몇 개 있는지 한눈에」가 목적이라 일부만 받으면
/// 목적이 깨진다. 서버가 200개로 묶으므로 그 이상은 오지 않는다.
struct MapPlacesResponse: Codable {
    let places: [MapPlace]
}

struct MapAPI {
    static func places() async throws -> [MapPlace] {
        let response: MapPlacesResponse =
            try await APIClient.shared.get("/home/places", query: ["limit": "200"])
        return response.places
    }
}
