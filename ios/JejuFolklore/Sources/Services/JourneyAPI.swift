import Foundation

private struct JourneyListResponse: Codable {
    let journeys: [Journey]
}

/// 여정 조회. **좌표를 보내지 않는다** — "지금 여기예요" 판정은 단말에서 한다.
struct JourneyAPI {
    static func list() async throws -> [Journey] {
        let response: JourneyListResponse =
            try await APIClient.shared.get("/journeys", query: [:])
        return response.journeys
    }

    static func detail(id: String) async throws -> Journey {
        try await APIClient.shared.get("/journeys/\(id)", query: [:])
    }
}
