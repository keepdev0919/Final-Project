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

    /// 장소-설화 연결 한 줄 (Lv2). 백엔드 미구현이면 throw → 호출부에서 무시.
    static func connection(codeNo: String, place: String) async throws -> String {
        let response: FolkloreConnectionResponse = try await APIClient.shared.get(
            "/pins/\(codeNo)/connection",
            query: ["place": place]
        )
        return response.connection
    }

    /// 풀스크린 스토리 뷰어용 5~7페이지 (Lv3).
    static func story(codeNo: String, place: String) async throws -> [StoryPage] {
        let response: FolkloreStoryResponse = try await APIClient.shared.get(
            "/pins/\(codeNo)/story",
            query: ["place": place]
        )
        return response.pages
    }
}
