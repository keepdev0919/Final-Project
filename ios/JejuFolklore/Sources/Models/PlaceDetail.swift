import Foundation

struct PlaceDetail: Decodable {
    let name: String
    let overview: String
    let images: [String]
    let address: String
    let tel: String
    let openTime: String
    let restDate: String
    let useFee: String
    let parking: String
    /// 반복정보 — 화장실·주차요금·해설 안내처럼 장소마다 다른 항목 (KTO detailInfo2).
    let info: [PlaceInfoRow]
    /// 무장애 여행정보 — 장애인 주차·화장실·휠체어 대여 등 (KTO KorWithService2).
    let accessibility: [PlaceInfoRow]

    enum CodingKeys: String, CodingKey {
        case name, overview, images, address, tel, openTime, restDate, useFee, parking
        case info, accessibility
    }

    /// 서버가 옛 캐시를 돌려줘도 새 칸이 없어서 화면 전체가 깨지지 않게 한다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name          = try c.decode(String.self, forKey: .name)
        overview      = try c.decodeIfPresent(String.self, forKey: .overview) ?? ""
        images        = try c.decodeIfPresent([String].self, forKey: .images) ?? []
        address       = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        tel           = try c.decodeIfPresent(String.self, forKey: .tel) ?? ""
        openTime      = try c.decodeIfPresent(String.self, forKey: .openTime) ?? ""
        restDate      = try c.decodeIfPresent(String.self, forKey: .restDate) ?? ""
        useFee        = try c.decodeIfPresent(String.self, forKey: .useFee) ?? ""
        parking       = try c.decodeIfPresent(String.self, forKey: .parking) ?? ""
        info          = try c.decodeIfPresent([PlaceInfoRow].self, forKey: .info) ?? []
        accessibility = try c.decodeIfPresent([PlaceInfoRow].self, forKey: .accessibility) ?? []
    }

    /// KTO 에 **소개할 거리가 있는가** — 소개글 탭을 보여줄지 정한다.
    var hasIntroduction: Bool { !overview.isEmpty || !images.isEmpty }
}

struct PlaceInfoRow: Decodable, Hashable {
    let label: String
    let value: String

    init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}
