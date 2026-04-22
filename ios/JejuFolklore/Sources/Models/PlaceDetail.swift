import Foundation

// APIClient.decoder가 .convertFromSnakeCase를 사용하므로
// image_url → imageUrl 자동 변환됨. CodingKeys 불필요.
struct PlaceDetail: Decodable {
    let name: String
    let overview: String
    let imageUrl: String
    let address: String
}
