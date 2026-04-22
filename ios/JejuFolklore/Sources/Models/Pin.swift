import Foundation

struct Pin: Codable, Identifiable, Equatable, Hashable {
    let codeNo: String
    let title: String
    let sourceType: String       // "legend" | "folktale"
    let summary: String
    let lat: Double
    let lng: Double
    let primaryPlace: String
    let distanceM: Double?

    var id: String { codeNo }

    var sourceTypeLabel: String {
        sourceType == "legend" ? "설화" : "민담"
    }
}
