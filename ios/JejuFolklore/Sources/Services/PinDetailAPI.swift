import Foundation

struct PinDetail: Codable, Identifiable {
    let codeNo: String
    let title: String
    let sourceType: String
    let summary: String
    let fullText: String
    let primaryPlace: String
    let lat: Double
    let lng: Double

    var id: String { codeNo }

    var sourceTypeLabel: String {
        sourceType == "legend" ? "전설" : "민담"
    }
}

struct PinDetailAPI {
    static func fetch(codeNo: String) async throws -> PinDetail {
        try await APIClient.shared.get("/pins/\(codeNo)", query: [:])
    }
}
