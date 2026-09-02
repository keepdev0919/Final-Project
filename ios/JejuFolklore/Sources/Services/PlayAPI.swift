import Foundation

/// PLAY · Place 조회.
///
/// ⚠️ **사용자 위치를 보내지 않는다.** 거리 계산은 전부 단말에서 한다
/// (`데이터.md` §6 · 위치기반서비스사업자 신고 회피).
enum PlayAPI {

    private struct PlaysResponse: Decodable { let plays: [PlaySummary] }

    private struct PinsResponse: Decodable {
        let pins: [PlayMapPin]
        let activeCount: Int
        let preparingCount: Int
    }

    /// 지도가 보여줄 것. 개수를 **서버가 세어서** 함께 준다 —
    /// 화면에 숫자를 박아두면 콘텐츠가 늘어날 때 조용히 거짓이 된다.
    struct MapPins {
        let pins: [PlayMapPin]
        let activeCount: Int
        let preparingCount: Int
    }

    /// 플레이할 수 있는 PLAY 전부.
    static func list() async throws -> [PlaySummary] {
        let r: PlaysResponse = try await APIClient.shared.get("/plays")
        return r.plays
    }

    /// PLAY 하나 전체 — Point · Mission · Step · Story 까지.
    static func detail(id: String) async throws -> Play {
        try await APIClient.shared.get("/plays/\(id)")
    }

    /// 이 장소에서 할 수 있는 PLAY. **비어 있는 것이 정상이다.**
    static func forPlace(placeId: String) async throws -> [PlaySummary] {
        let r: PlaysResponse = try await APIClient.shared.get("/places/\(placeId)/plays")
        return r.plays
    }

    static func mapPins() async throws -> MapPins {
        let r: PinsResponse = try await APIClient.shared.get("/map/pins")
        return MapPins(pins: r.pins, activeCount: r.activeCount,
                       preparingCount: r.preparingCount)
    }
}
