import Foundation

struct CoursePlace: Codable, Identifiable, Equatable, Hashable {
    let name: String
    let lat: Double
    let lng: Double
    let day: Int
    let startTime: String?
    let folklorePins: [Pin]

    init(name: String, lat: Double, lng: Double, day: Int,
         startTime: String? = nil, folklorePins: [Pin] = []) {
        self.name = name
        self.lat = lat
        self.lng = lng
        self.day = day
        self.startTime = startTime
        self.folklorePins = folklorePins
    }

    var id: String { "\(name)-\(day)" }
}
