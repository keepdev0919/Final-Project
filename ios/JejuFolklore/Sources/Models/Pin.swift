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

    /// "C_M_001 각시당본풀이" → "각시당본풀이" (코드 접두사 제거)
    var displayTitle: String {
        if let space = title.firstIndex(of: " ") {
            let after = title[title.index(after: space)...]
            if !after.isEmpty { return String(after) }
        }
        return title
    }
}
