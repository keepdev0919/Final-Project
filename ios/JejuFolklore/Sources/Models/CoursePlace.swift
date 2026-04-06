import Foundation

struct CoursePlace: Codable, Identifiable, Equatable {
    let name: String
    let lat: Double
    let lng: Double
    let day: Int
    let startTime: String?
    let folklorePins: [Pin]

    var id: String { "\(name)-\(day)" }
}
