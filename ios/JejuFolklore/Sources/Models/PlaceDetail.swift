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
}
