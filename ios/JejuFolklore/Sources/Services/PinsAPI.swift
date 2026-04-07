import Foundation

struct PinsAPI {
    static func fetchAll() async throws -> [Pin] {
        try await APIClient.shared.get("/pins/all", query: [:])
    }

    static func fetch(lat: Double, lng: Double, radiusM: Double = 500) async throws -> [Pin] {
        try await APIClient.shared.get("/pins", query: [
            "lat": String(lat),
            "lng": String(lng),
            "radius_m": String(radiusM)
        ])
    }
}
