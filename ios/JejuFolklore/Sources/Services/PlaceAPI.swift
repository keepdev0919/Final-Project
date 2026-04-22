import Foundation

enum PlaceAPI {
    static func detail(name: String, lat: Double, lng: Double) async throws -> PlaceDetail {
        try await APIClient.shared.get(
            "/place/detail",
            query: ["name": name, "lat": String(lat), "lng": String(lng)]
        )
    }
}
