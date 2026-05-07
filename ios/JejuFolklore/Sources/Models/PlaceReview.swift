import Foundation

struct PlaceReviewsResponse: Decodable {
    let total: Int
    let tagCounts: [String: Int]
    let recentNotes: [String]
}

struct PlaceReviewBody: Encodable {
    let placeName: String
    let tags: [String]
    let note: String?
    let deviceId: String
}
